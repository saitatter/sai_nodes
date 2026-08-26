enum CallbackType {
  success,
  error,
  warning,
  info,
}

typedef Callback = void Function(CallbackType type, String message);
