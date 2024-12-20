import 'hlc.dart';
import 'hlc.utils.dart';

class HLCState {
  late HLC _clock;

  late final HLCUtils hlcUtils;

  HLCState._(this._clock, this.hlcUtils);

  static HLCState create({required String deviceId}) {
    final clock = HLC.now(deviceId);
    final hlcUtils = HLCUtils(deviceId);
    return HLCState._(clock, hlcUtils);
  }

  String sendMessage() {
    _clock = hlcUtils.send(_clock);
    return hlcUtils.pack(_clock);
  }

  void receiveMessage(String hlcAsString) {
    final hlcReceived = hlcUtils.unpack(hlcAsString);
    _clock = hlcUtils.receive(_clock, hlcReceived);
  }
}
