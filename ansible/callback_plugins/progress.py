# Вывод Ansible по умолчанию + ход долгих задач в одной перезаписываемой строке;
# для Helm — состояние подов namespace из имени задачи «... kubectl get pods -n <ns>)».
import re
import shutil
import subprocess
import sys
import time

from ansible.plugins.callback.default import CallbackModule as DefaultCallbackModule

DOCUMENTATION = """
name: progress
type: stdout
short_description: вывод по умолчанию с ходом выполнения долгих задач
description:
  - Как default, но фоновые задачи и повторы ожидания показывают ход в одной строке.
extends_documentation_fragment:
  - default_callback
  - result_format_callback
"""

NAMESPACE = re.compile(r"kubectl get pods -n ([\w-]+)")


class CallbackModule(DefaultCallbackModule):
    CALLBACK_VERSION = 2.0
    CALLBACK_TYPE = "stdout"
    CALLBACK_NAME = "progress"

    _line_open = False
    _task_started = 0.0
    _namespace = None

    def _elapsed(self):
        seconds = int(time.monotonic() - self._task_started)
        return f"{seconds // 60} мин {seconds % 60:02d} с"

    def _pods(self):
        """Краткое состояние подов: «готово 3/5; ждём: имя статус, ...»."""
        try:
            output = subprocess.run(
                ["kubectl", "get", "pods", "-n", self._namespace, "--no-headers"],
                capture_output=True, text=True, timeout=10,
            ).stdout
        except (OSError, subprocess.TimeoutExpired):
            return ""
        pods = [line.split() for line in output.splitlines() if len(line.split()) >= 3]
        if not pods:
            return "подов пока нет"
        waiting = [
            f"{name} {status}" for name, ready, status, *_ in pods
            if status != "Completed" and ready.split("/")[0] != ready.split("/")[-1]
        ]
        text = f"готово {len(pods) - len(waiting)}/{len(pods)}"
        return text + (f"; ждём: {', '.join(waiting)}" if waiting else "")

    def _show(self, text):
        if sys.stdout.isatty():
            width = shutil.get_terminal_size().columns - 1
            sys.stdout.write("\r\033[K" + text[:width])
            sys.stdout.flush()
            self._line_open = True
        else:
            self._display.display(text)

    def _close_line(self):
        if self._line_open:
            sys.stdout.write("\n")
            sys.stdout.flush()
            self._line_open = False

    def v2_playbook_on_task_start(self, task, is_conditional):
        self._close_line()
        self._task_started = time.monotonic()
        match = NAMESPACE.search(task.get_name())
        self._namespace = match.group(1) if match else None
        super().v2_playbook_on_task_start(task, is_conditional)

    def v2_runner_on_async_poll(self, result):
        details = f": {self._pods()}" if self._namespace else ""
        self._show(f"  … {self._elapsed()}{details}")

    def v2_runner_retry(self, result):
        left = result._result.get("retries", 0) - result._result.get("attempts", 0)
        self._show(f"  … {self._elapsed()}: ожидание, осталось попыток {left}")

    # Итог фоновой задачи печатают v2_runner_on_ok/failed — без строк ASYNC OK/FAILED.
    def v2_runner_on_async_ok(self, result):
        self._close_line()

    def v2_runner_on_async_failed(self, result):
        self._close_line()

    def v2_runner_on_ok(self, result):
        self._close_line()
        super().v2_runner_on_ok(result)

    def v2_runner_on_failed(self, result, ignore_errors=False):
        self._close_line()
        super().v2_runner_on_failed(result, ignore_errors)

    def v2_runner_on_skipped(self, result):
        self._close_line()
        super().v2_runner_on_skipped(result)

    def v2_runner_on_unreachable(self, result):
        self._close_line()
        super().v2_runner_on_unreachable(result)

    def v2_playbook_on_stats(self, stats):
        self._close_line()
        super().v2_playbook_on_stats(stats)
