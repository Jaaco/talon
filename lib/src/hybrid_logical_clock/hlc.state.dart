import 'hlc.dart';
import 'hlc.utils.dart';

/// Manages the state of a Hybrid Logical Clock for a single node/device.
///
/// This class maintains the current HLC state and provides methods to:
/// - Generate new timestamps when sending messages ([send])
/// - Update the clock when receiving messages ([receive])
class HLCState {
  HLC _clock;
  final HLCUtils _hlcUtils;

  HLCState._(this._clock, this._hlcUtils);

  /// Create a new HLCState for the given node/device ID.
  factory HLCState(String nodeId) {
    final clock = HLC.now(nodeId);
    final hlcUtils = HLCUtils(nodeId);
    return HLCState._(clock, hlcUtils);
  }

  /// The current HLC value.
  HLC get current => _clock;

  /// Generate a new HLC timestamp for sending a message.
  ///
  /// This advances the clock and returns the new HLC.
  /// The returned HLC should be used as the timestamp for the message.
  HLC send() {
    _clock = _hlcUtils.send(_clock);
    return _clock;
  }

  /// Update the clock after receiving a message with the given HLC.
  ///
  /// This ensures our clock is at least as advanced as the received clock,
  /// maintaining causal ordering.
  void receive(HLC remote) {
    _clock = _hlcUtils.receive(_clock, remote);
  }

  /// Update the clock from a packed HLC string.
  ///
  /// Returns true if the string was valid and the clock was updated.
  bool receiveFromString(String packed) {
    final remote = HLC.tryParse(packed);
    if (remote == null) return false;
    receive(remote);
    return true;
  }
}
