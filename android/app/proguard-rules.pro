# Required by flutter_onnxruntime/image_background_remover. ONNX Runtime's
# native bridge looks up these Java classes and members by their original name.
-keep class ai.onnxruntime.** { *; }

# google_mlkit_text_recognition compiles optional recognizers into its shared
# bridge. Raze Store bundles only the Latin recognizer, so R8 may safely ignore
# references to the uninstalled script-specific modules.
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.chinese.ChineseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.devanagari.DevanagariTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.japanese.JapaneseTextRecognizerOptions
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions$Builder
-dontwarn com.google.mlkit.vision.text.korean.KoreanTextRecognizerOptions
