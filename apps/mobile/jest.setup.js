jest.mock("react-native-safe-area-context", () => {
  const React = require("react");
  const { View } = require("react-native");
  return {
    SafeAreaProvider: ({ children }) => React.createElement(View, null, children),
    SafeAreaView: ({ children, style }) =>
      React.createElement(View, { style }, children),
    useSafeAreaInsets: () => ({ top: 0, right: 0, bottom: 0, left: 0 }),
  };
});

jest.mock("./specs/PlaypathPlayerViewNativeComponent", () => {
  const React = require("react");
  const { View } = require("react-native");
  const Native = React.forwardRef((props, ref) =>
    React.createElement(View, { ...props, ref, testID: "player" }),
  );
  return {
    __esModule: true,
    default: Native,
    Commands: {
      play: jest.fn(),
      pause: jest.fn(),
      seek: jest.fn(),
    },
  };
});
