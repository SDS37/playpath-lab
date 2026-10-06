import {
  loadReceiver,
  receiverFailure,
  ReceiverSuperseded,
  stopReceiver,
} from "./receiver";

const video = document.querySelector("#picture");
const status = document.querySelector("#status");

if (video instanceof HTMLVideoElement && status instanceof HTMLElement) {
  let failed = false;
  void loadReceiver(video, undefined, (err) => {
    failed = true;
    status.textContent = receiverFailure(err);
  })
    .then(() => {
      if (failed) {
        return;
      }
      status.textContent = "Loaded";
      void video.play().catch(() => undefined);
    })
    .catch((err: unknown) => {
      if (err instanceof ReceiverSuperseded) {
        return;
      }
      status.textContent = receiverFailure(err);
    });
  window.addEventListener("pagehide", () => {
    void stopReceiver();
  });
}
