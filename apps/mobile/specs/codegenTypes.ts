import type { NativeSyntheticEvent } from "react-native";

/** Names the Fabric codegen parser recognizes. The definitions stay out of the spec file so they are not expanded. */
export type Int32 = number;

export type BubblingEventHandler<T> = (
  event: NativeSyntheticEvent<T>,
) => void | Promise<void>;
