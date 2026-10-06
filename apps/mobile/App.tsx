import { useRef, useState } from "react";
import { StyleSheet, View } from "react-native";
import { SafeAreaProvider, SafeAreaView } from "react-native-safe-area-context";
import { Controls } from "./src/Controls";
import { PlayerView } from "./src/PlayerView";
import type { PlayerCommands } from "./src/PlayerSurface";
import { initialSnapshot, type PlaybackSnapshot } from "./src/snapshot";
import { theme } from "./src/theme";

function App() {
  const commands = useRef<PlayerCommands>(null);
  const [snapshot, setSnapshot] = useState<PlaybackSnapshot>(initialSnapshot);

  return (
    <SafeAreaProvider>
      <SafeAreaView style={styles.screen}>
        <PlayerView
          ref={commands}
          onSnapshot={setSnapshot}
          onPlaybackEvent={(json) => {
            console.info(json);
          }}
        />
        <Controls
          snapshot={snapshot}
          onPlay={() => {
            commands.current?.play();
          }}
          onPause={() => {
            commands.current?.pause();
          }}
          onSeek={(positionMs) => {
            commands.current?.seek(positionMs);
          }}
        />
      </SafeAreaView>
    </SafeAreaProvider>
  );
}

const styles = StyleSheet.create({
  screen: {
    backgroundColor: theme.background,
    flex: 1,
  },
});

export default App;
