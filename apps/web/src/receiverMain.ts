import { loadReceiver, receiverFailure, stopReceiver } from "./receiver";

const video = document.querySelector("#picture");
const status = document.querySelector("#status");

if (video instanceof HTMLVideoElement && status instanceof HTMLElement) {
  void loadReceiver(video)
    .then(() => {
      status.textContent = "Loaded";
      void video.play().catch(() => undefined);
    })
    .catch((err: unknown) => {
      status.textContent = receiverFailure(err);
    });
  window.addEventListener("pagehide", () => {
    void stopReceiver();
  });
}
