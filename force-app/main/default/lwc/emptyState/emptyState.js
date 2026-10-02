import { LightningElement, api } from "lwc";

const VARIANTS = ["first-use", "filtered", "failed"];

// Icon and default role per variant.
const ICON_BY_VARIANT = {
  "first-use": "utility:add",
  filtered: "utility:filterList",
  failed: "utility:error"
};

export default class EmptyState extends LightningElement {
  @api heading;
  @api body;
  @api ctaLabel;
  @api secondaryLabel;
  @api reference;

  _variant = "first-use";

  @api
  get variant() {
    return this._variant;
  }
  set variant(value) {
    this._variant = VARIANTS.includes(value) ? value : "first-use";
  }

  get icon() {
    return ICON_BY_VARIANT[this._variant];
  }

  get roleValue() {
    return this._variant === "failed" ? "alert" : "status";
  }

  get containerClass() {
    return `empty empty_${this._variant}`;
  }

  get showReference() {
    return this._variant === "failed" && !!this.reference;
  }

  handlePrimaryAction() {
    this.dispatchEvent(new CustomEvent("primaryaction"));
  }

  handleSecondaryAction() {
    this.dispatchEvent(new CustomEvent("secondaryaction"));
  }
}
