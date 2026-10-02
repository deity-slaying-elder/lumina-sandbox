import { LightningElement, api } from "lwc";

const TONES = ["success", "warning", "error", "info", "neutral"];

// Default icon per tone, used unless the consumer overrides with iconName.
const DEFAULT_ICON_BY_TONE = {
  success: "utility:check",
  warning: "utility:warning",
  error: "utility:error",
  info: "utility:info",
  neutral: "utility:dash"
};

export default class StatusChip extends LightningElement {
  @api label;
  @api iconName;

  _tone = "neutral";

  @api
  get tone() {
    return this._tone;
  }
  set tone(value) {
    // Anything outside the known tone list falls back to neutral.
    this._tone = TONES.includes(value) ? value : "neutral";
  }

  get icon() {
    return this.iconName || DEFAULT_ICON_BY_TONE[this._tone];
  }

  get chipClass() {
    return `chip chip_${this._tone}`;
  }
}
