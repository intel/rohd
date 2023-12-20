class SignalService {
  Map<String, dynamic> filterSignals(
    Map<String, dynamic> signals,
    String searchTerm,
  ) {
    Map<String, dynamic> filtered = {};

    signals.forEach((key, value) {
      if (key.toLowerCase().contains(searchTerm.toLowerCase())) {
        filtered[key] = value;
      }
    });

    return filtered;
  }
}
