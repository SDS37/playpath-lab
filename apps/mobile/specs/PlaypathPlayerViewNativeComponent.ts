import type { BubblingEventHandler, Int32 } from "./codegenTypes";
import {
  codegenNativeComponent,
  type HostComponent,
  type ViewProps,
} from "react-native";
import * as React from "react";

type PlaybackEventPayload = Readonly<{
  json: string;
}>;

type SnapshotEventPayload = Readonly<{
  playbackState: string;
  stalled: boolean;
  adPlaying: boolean;
  positionMs: Int32;
  durationMs: Int32;
  error: string;
}>;

export interface NativeProps extends ViewProps {
  manifestUrl?: string;
  onPlaybackEvent?: BubblingEventHandler<PlaybackEventPayload>;
  onSnapshot?: BubblingEventHandler<SnapshotEventPayload>;
}

type NativeType = HostComponent<NativeProps>;

interface NativeCommands {
  play: (viewRef: React.ElementRef<NativeType>) => void;
  pause: (viewRef: React.ElementRef<NativeType>) => void;
  seek: (viewRef: React.ElementRef<NativeType>, positionMs: Int32) => void;
}

type CommandsRuntime = <T extends object>(options: {
  readonly supportedCommands: readonly (keyof T & string)[];
}) => T;

declare function require(moduleName: string): { default: CommandsRuntime };

function codegenNativeCommands<T extends object>(options: {
  readonly supportedCommands: readonly (keyof T & string)[];
}): T {
  return require(
    "react-native/Libraries/Utilities/codegenNativeCommands",
  ).default<T>(options);
}

export const Commands: NativeCommands = codegenNativeCommands<NativeCommands>({
  supportedCommands: ["play", "pause", "seek"],
});

export default codegenNativeComponent<NativeProps>("PlaypathPlayerView");
