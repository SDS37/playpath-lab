import Ajv2020 from "ajv/dist/2020.js";
import schema from "../schema/playback-event.v1.json" with { type: "json" };

const ajv = new Ajv2020({ allErrors: true, strict: true });
const validate = ajv.compile(schema);

/** Returns schema failures for `event`. An empty list means the event matches version 1. */
export function playbackEventErrors(event: unknown): string[] {
  if (validate(event)) {
    return [];
  }
  return (validate.errors ?? []).map((error) => {
    const where = error.instancePath === "" ? "(root)" : error.instancePath;
    const named =
      "additionalProperty" in error.params &&
      typeof error.params.additionalProperty === "string"
        ? `: ${error.params.additionalProperty}`
        : "";
    return `${where} ${error.message ?? "is invalid"}${named}`;
  });
}
