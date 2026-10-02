// This module has no behaviour of its own. Jest's LWC module resolver only looks
// for a .ts, .js or .html file when resolving "c/uiTokens", so a bare .css module
// cannot be found without this re-export. It re-exports the compiled stylesheet
// so `@import 'c/uiTokens';` resolves the same way here as it does when compiled
// by the platform.
export { default } from "./uiTokens.css";
