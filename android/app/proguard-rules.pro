# Required by flutter_onnxruntime/image_background_remover. ONNX Runtime's
# native bridge looks up these Java classes and members by their original name.
-keep class ai.onnxruntime.** { *; }
