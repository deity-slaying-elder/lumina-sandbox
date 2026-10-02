import React from "react";
import { Composition } from "remotion";
import { Film, FILM_SECS } from "./Film";
import { FPS, sec } from "./theme";

export const RemotionRoot: React.FC = () => (
  <Composition
    id="Film"
    component={Film}
    durationInFrames={sec(FILM_SECS)}
    fps={FPS}
    width={1920}
    height={1080}
  />
);
