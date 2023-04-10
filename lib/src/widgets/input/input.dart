import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_chat_types/flutter_chat_types.dart' as types;
import 'package:avatar_glow/avatar_glow.dart';
import 'package:holding_gesture/holding_gesture.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../models/input_clear_mode.dart';
import '../../models/send_button_visibility_mode.dart';
import '../../util.dart';
import '../state/inherited_chat_theme.dart';
import '../state/inherited_l10n.dart';
import 'attachment_button.dart';
import 'audio_button.dart';
import 'audio_recorder.dart';
import 'input_text_field_controller.dart';
import 'send_button.dart';

/// A class that represents bottom bar widget with a text field, attachment and
/// send buttons inside. By default hides send button when text field is empty.
class Input extends StatefulWidget {
  /// Creates [Input] widget.
  Input({
    super.key,
    this.isAttachmentUploading,
    this.onAttachmentPressed,
    required this.onSendPressed,
    this.options = const InputOptions(),
    this.isAudioUploading,
    this.onAudioRecorded,
    this.isAutoSpeak = false,
    this.onIsAutoSpeak,
  });

  /// See [AudioButton.onPressed].
  final Future<bool> Function({
    required Duration length,
    required String filePath,
    required List<double> waveForm,
  })? onAudioRecorded;

  /// Whether audio recording is uploading. Will replace audio button with a
  /// [CircularProgressIndicator]. Since we don't handle the upload of the audio
  /// we have no way of knowing if something is uploading so you need to set
  /// this manually.
  final bool? isAudioUploading;

  /// Whether attachment is uploading. Will replace attachment button with a
  /// [CircularProgressIndicator]. Since we don't have libraries for
  /// managing media in dependencies we have no way of knowing if
  /// something is uploading so you need to set this manually.
  final bool? isAttachmentUploading;

  /// See [AttachmentButton.onPressed].
  final VoidCallback? onAttachmentPressed;

  final void Function(bool value)? onIsAutoSpeak;

  /// Will be called on [SendButton] tap. Has [types.PartialText] which can
  /// be transformed to [types.TextMessage] and added to the messages list.
  final void Function(types.PartialText) onSendPressed;

  /// Customisation options for the [Input].
  final InputOptions options;

  bool isAutoSpeak = false;

  @override
  State<Input> createState() => _InputState();
}

/// [Input] widget state.
class _InputState extends State<Input> {
  final _audioRecorderKey = GlobalKey<AudioRecorderState>();
  SpeechToText _speechToText = SpeechToText();
  bool _speechEnabled = false;
  String _lastWords = '';

  /// This has to happen only once per app
  void _initSpeech() async {
    _speechEnabled = await _speechToText.initialize();
    setState(() {});
  }

  /// Each time to start a speech recognition session
  void _startListening() async {
    if (!_speechEnabled) {
      _initSpeech();
    }
    await _speechToText.listen(onResult: _onSpeechResult);
    setState(() {
      _recordingAudio = true;
    });
  }

  /// Manually stop the active speech recognition session
  /// Note that there are also timeouts that each platform enforces
  /// and the SpeechToText plugin supports setting timeouts on the
  /// listen method.
  void _stopListening() async {
    await _speechToText.stop();
    setState(() {
      _recordingAudio = false;
    });
  }

  /// This is the callback that the SpeechToText plugin calls when
  /// the platform returns recognized words.
  void _onSpeechResult(SpeechRecognitionResult result) {
    setState(() {
      _lastWords = result.recognizedWords;
      _textController.text = result.recognizedWords;
    });
  }

  late final _inputFocusNode = FocusNode(
    onKeyEvent: (node, event) {
      if (event.physicalKey == PhysicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.physicalKeysPressed.any(
            (el) => <PhysicalKeyboardKey>{
              PhysicalKeyboardKey.shiftLeft,
              PhysicalKeyboardKey.shiftRight,
            }.contains(el),
          )) {
        if (event is KeyDownEvent) {
          _handleSendPressed();
        }
        return KeyEventResult.handled;
      } else {
        return KeyEventResult.ignored;
      }
    },
  );

  bool _sendButtonVisible = false;
  bool _recordingAudio = false;
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    _initSpeech();

    _textController =
        widget.options.textEditingController ?? InputTextFieldController();
    _handleSendButtonVisibilityModeChange();
  }

  @override
  void didUpdateWidget(covariant Input oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.options.sendButtonVisibilityMode !=
        oldWidget.options.sendButtonVisibilityMode) {
      _handleSendButtonVisibilityModeChange();
    }
  }

  @override
  void dispose() {
    _inputFocusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => _inputFocusNode.requestFocus(),
        child: _inputBuilder(),
      );

  void _handleSendButtonVisibilityModeChange() {
    _textController.removeListener(_handleTextControllerChange);
    if (widget.options.sendButtonVisibilityMode ==
        SendButtonVisibilityMode.hidden) {
      _sendButtonVisible = false;
    } else if (widget.options.sendButtonVisibilityMode ==
        SendButtonVisibilityMode.editing) {
      _sendButtonVisible = _textController.text.trim() != '';
      _textController.addListener(_handleTextControllerChange);
    } else {
      _sendButtonVisible = true;
    }
  }

  void _handleSendPressed() {
    final trimmedText = _textController.text.trim();
    if (trimmedText != '') {
      final partialText = types.PartialText(text: trimmedText);
      widget.onSendPressed(partialText);

      if (widget.options.inputClearMode == InputClearMode.always) {
        _textController.clear();
      }
    }
  }

  void _handleTextControllerChange() {
    setState(() {
      _sendButtonVisible = _textController.text.trim() != '';
    });
  }

  Widget _audioWidget() {
    if (widget.isAudioUploading == true) {
      return SizedBox(
        height: 24,
        width: 24,
        child: CircularProgressIndicator(
          backgroundColor: Colors.transparent,
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(
            InheritedChatTheme.of(context).theme.inputTextColor,
          ),
        ),
      );
    } else {
      return AudioButton(
        onPressed: _toggleRecording,
        recordingAudio: _recordingAudio,
      );
    }
  }

  Future<void> _toggleRecording() async {
    if (!_recordingAudio) {
      setState(() {
        _recordingAudio = true;
      });
    } else {
      final audioRecording =
          await _audioRecorderKey.currentState!.stopRecording();
      if (audioRecording != null) {
        final success = await widget.onAudioRecorded!(
          length: audioRecording.duration,
          filePath: audioRecording.filePath,
          waveForm: audioRecording.decibelLevels,
        );
        if (success) {
          setState(() {
            _recordingAudio = false;
          });
        }
      }
    }
  }

  void _cancelRecording() async {
    setState(() {
      _recordingAudio = false;
    });
  }

  Widget _inputBuilder() {
    final query = MediaQuery.of(context);
    final buttonPadding = InheritedChatTheme.of(context)
        .theme
        .inputPadding
        .copyWith(left: 16, right: 16);
    final safeAreaInsets = isMobile
        ? EdgeInsets.fromLTRB(
            query.padding.left,
            0,
            query.padding.right,
            query.viewInsets.bottom + query.padding.bottom,
          )
        : EdgeInsets.zero;
    final textPadding = InheritedChatTheme.of(context)
        .theme
        .inputPadding
        .copyWith(left: 0, right: 0)
        .add(
          EdgeInsets.fromLTRB(
            widget.onAttachmentPressed != null ? 0 : 24,
            0,
            _sendButtonVisible ? 0 : 24,
            0,
          ),
        );

    return Stack(
      children: [
        Focus(
          autofocus: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Material(
              // borderRadius: InheritedChatTheme.of(context).theme.inputBorderRadius,
              borderRadius: BorderRadius.circular(20),
              color: InheritedChatTheme.of(context).theme.inputBackgroundColor,
              child: Container(
                decoration: InheritedChatTheme.of(context)
                    .theme
                    .inputContainerDecoration,
                padding: safeAreaInsets,
                child: Row(
                  textDirection: TextDirection.ltr,
                  children: [
                    if (widget.onAttachmentPressed != null)
                      AttachmentButton(
                        isLoading: widget.isAttachmentUploading ?? false,
                        onPressed: widget.onAttachmentPressed,
                        padding: buttonPadding,
                      ),
                    // if (_recordingAudio)
                    //   Expanded(
                    //     child: AudioRecorder(
                    //       key: _audioRecorderKey,
                    //       onCancelRecording: _cancelRecording,
                    //     ),
                    //   ),
                    Expanded(
                      child: Padding(
                        padding: textPadding,
                        child: TextField(
                          controller: _textController,
                          cursorColor: InheritedChatTheme.of(context)
                              .theme
                              .inputTextCursorColor,
                          decoration: InheritedChatTheme.of(context)
                              .theme
                              .inputTextDecoration
                              .copyWith(
                                hintStyle: InheritedChatTheme.of(context)
                                    .theme
                                    .inputTextStyle
                                    .copyWith(
                                      color: InheritedChatTheme.of(context)
                                          .theme
                                          .inputTextColor
                                          .withOpacity(0.5),
                                    ),
                                hintText: InheritedL10n.of(context)
                                    .l10n
                                    .inputPlaceholder,
                              ),
                          focusNode: _inputFocusNode,
                          keyboardType: TextInputType.multiline,
                          maxLines: 5,
                          minLines: 1,
                          onChanged: widget.options.onTextChanged,
                          onTap: widget.options.onTextFieldTap,
                          style: InheritedChatTheme.of(context)
                              .theme
                              .inputTextStyle
                              .copyWith(
                                color: InheritedChatTheme.of(context)
                                    .theme
                                    .inputTextColor,
                              ),
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            buttonPadding.bottom + buttonPadding.top + 24,
                      ),
                      child: Visibility(
                        visible: _sendButtonVisible,
                        child: SendButton(
                          onPressed: _handleSendPressed,
                        ),
                      ),
                    ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight:
                            buttonPadding.bottom + buttonPadding.top + 24,
                      ),
                      child: Visibility(
                        visible: widget.onAudioRecorded != null &&
                            !_sendButtonVisible,
                        child: _audioWidget(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Align(
          heightFactor: 1.6,
          alignment: AlignmentDirectional.bottomCenter,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            HoldTimeoutDetector(
              onTimeout: _stopListening,
              onTimerInitiated: _startListening,
              enableHapticFeedback: true,
              onCancel: _stopListening,
              holdTimeout: const Duration(milliseconds: 30000),
              child: AvatarGlow(
                animate: _recordingAudio,
                glowColor: InheritedChatTheme.of(context).theme.primaryColor,
                endRadius: 50.0,
                duration: const Duration(milliseconds: 1000),
                repeatPauseDuration: const Duration(milliseconds: 100),
                repeat: true,
                child: Material(
                  elevation: 8.0,
                  shape: CircleBorder(),
                  child: CircleAvatar(
                    // backgroundColor: Colors.grey[100],
                    backgroundColor: InheritedChatTheme.of(context)
                        .theme
                        .inputBackgroundColor,
                    child: const Icon(
                      Icons.mic,
                      size: 35,
                    ),
                    radius: 30,
                  ),
                ),
              ),
            ),
          ]),
        ),
        if (widget.onIsAutoSpeak != null)
          Align(
            heightFactor: 2.2,
            alignment: Alignment.bottomRight,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Column(
                children: [
                  Switch(
                    onChanged: (value) {
                      setState(() {
                        widget.isAutoSpeak = value;
                      });
                      widget.onIsAutoSpeak!(value);
                    },
                    activeColor: InheritedChatTheme.of(context)
                        .theme
                        .sentMessageDocumentIconColor,
                    value: widget.isAutoSpeak,
                  ),
                  Text(
                    'Auto Speaker',
                    style: TextStyle(color: Colors.white54),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

@immutable
class InputOptions {
  const InputOptions({
    this.inputClearMode = InputClearMode.always,
    this.onTextChanged,
    this.onTextFieldTap,
    this.sendButtonVisibilityMode = SendButtonVisibilityMode.editing,
    this.textEditingController,
  });

  /// Controls the [Input] clear behavior. Defaults to [InputClearMode.always].
  final InputClearMode inputClearMode;

  /// Will be called whenever the text inside [TextField] changes.
  final void Function(String)? onTextChanged;

  /// Will be called on [TextField] tap.
  final VoidCallback? onTextFieldTap;

  /// Controls the visibility behavior of the [SendButton] based on the
  /// [TextField] state inside the [Input] widget.
  /// Defaults to [SendButtonVisibilityMode.editing].
  final SendButtonVisibilityMode sendButtonVisibilityMode;

  /// Custom [TextEditingController]. If not provided, defaults to the
  /// [InputTextFieldController], which extends [TextEditingController] and has
  /// additional fatures like markdown support. If you want to keep additional
  /// features but still need some methods from the default [TextEditingController],
  /// you can create your own [InputTextFieldController] (imported from this lib)
  /// and pass it here.
  final TextEditingController? textEditingController;
}
