class WebDataState<T> {
  const WebDataState({
    required this.loading,
    this.data,
    this.error,
  });

  const WebDataState.loading() : this(loading: true);

  const WebDataState.data(T value)
      : this(
          loading: false,
          data: value,
        );

  const WebDataState.error(Object value, {T? lastData})
      : this(
          loading: false,
          data: lastData,
          error: value,
        );

  final bool loading;
  final T? data;
  final Object? error;
}
