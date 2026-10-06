#import "PlaypathPlayerView.h"

#import <react/renderer/components/PlaypathPlayerViewSpec/ComponentDescriptors.h>
#import <react/renderer/components/PlaypathPlayerViewSpec/EventEmitters.h>
#import <react/renderer/components/PlaypathPlayerViewSpec/Props.h>
#import <react/renderer/components/PlaypathPlayerViewSpec/RCTComponentViewHelpers.h>

#import "PlaypathMobile-Swift.h"

using namespace facebook::react;

@interface PlaypathPlayerView () <RCTPlaypathPlayerViewViewProtocol>
@end

@implementation PlaypathPlayerView {
  PlaypathSession *_session;
}

- (instancetype)init
{
  if (self = [super init]) {
    _session = [PlaypathSession new];
    __weak PlaypathPlayerView *weakSelf = self;
    _session.onPlaybackEvent = ^(NSString *json) {
      [weakSelf emitPlaybackEvent:json];
    };
    _session.onSnapshot = ^(NSDictionary *payload) {
      [weakSelf emitSnapshot:payload];
    };
    [_session attachTo:self];
  }
  return self;
}

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps
{
  const auto &newProps = *std::static_pointer_cast<const PlaypathPlayerViewProps>(props);
  NSString *url = [NSString stringWithUTF8String:newProps.manifestUrl.c_str()];
  if (url != nil) {
    [_session loadWithManifestUrl:url];
  }
  [super updateProps:props oldProps:oldProps];
}

- (void)handleCommand:(const NSString *)commandName args:(const NSArray *)args
{
  RCTPlaypathPlayerViewHandleCommand(self, commandName, args);
}

- (void)play
{
  [_session play];
}

- (void)pause
{
  [_session pause];
}

- (void)seek:(int)positionMs
{
  [_session seekWithPositionMs:positionMs];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [_session layoutIn:self];
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  [_session pause];
}

- (void)dealloc
{
  [_session releasePlayer];
}

- (void)emitPlaybackEvent:(NSString *)json
{
  if (_eventEmitter == nullptr || json == nil) {
    return;
  }
  std::string body = std::string([json UTF8String]);
  PlaypathPlayerViewEventEmitter::OnPlaybackEvent event{body};
  self.eventEmitter.onPlaybackEvent(event);
}

- (void)emitSnapshot:(NSDictionary *)payload
{
  if (_eventEmitter == nullptr || payload == nil) {
    return;
  }
  std::string state = std::string([payload[@"playbackState"] UTF8String] ?: "");
  std::string error = std::string([payload[@"error"] UTF8String] ?: "");
  PlaypathPlayerViewEventEmitter::OnSnapshot snapshot{
    state,
    [payload[@"stalled"] boolValue],
    [payload[@"adPlaying"] boolValue],
    [payload[@"positionMs"] intValue],
    [payload[@"durationMs"] intValue],
    error,
  };
  self.eventEmitter.onSnapshot(snapshot);
}

- (const PlaypathPlayerViewEventEmitter &)eventEmitter
{
  return static_cast<const PlaypathPlayerViewEventEmitter &>(*_eventEmitter);
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<PlaypathPlayerViewComponentDescriptor>();
}

@end

extern "C" Class<RCTComponentViewProtocol> PlaypathPlayerViewCls(void)
{
  return PlaypathPlayerView.class;
}
