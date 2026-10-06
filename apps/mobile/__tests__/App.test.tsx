import React from "react";
import ReactTestRenderer from "react-test-renderer";
import App from "../App";

test("renders the title and the play control", async () => {
  let renderer: ReactTestRenderer.ReactTestRenderer;
  await ReactTestRenderer.act(() => {
    renderer = ReactTestRenderer.create(<App />);
  });
  expect(renderer!.root.findByProps({ accessibilityLabel: "playpath-bars" })).toBeTruthy();
  expect(renderer!.root.findByProps({ accessibilityLabel: "Play" })).toBeTruthy();
});
