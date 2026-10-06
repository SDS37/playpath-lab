import { StrictMode } from "react";
import { createRoot } from "react-dom/client";
import { PlayerScreen } from "./PlayerScreen";
import "./player/player.css";

const root = document.getElementById("root");
if (root === null) {
  throw new Error("root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <PlayerScreen />
  </StrictMode>,
);
