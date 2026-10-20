{{- define "llama.modelFile" -}}
{{- .Values.llama.model.file | default (printf "%s-%s.gguf" .Values.llama.model.name .Values.llama.model.quantization) -}}
{{- end -}}
