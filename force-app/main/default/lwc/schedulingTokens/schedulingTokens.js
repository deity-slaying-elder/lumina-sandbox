// No behaviour of its own. Jest's LWC module resolver only looks for a .ts, .js or
// .html file when resolving "c/schedulingTokens", so a bare .css module cannot be
// found without this re-export.
export { default } from "./schedulingTokens.css";
