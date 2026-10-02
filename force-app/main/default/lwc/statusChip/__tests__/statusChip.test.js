import { createElement } from "lwc";
import StatusChip from "c/statusChip";

describe("c-status-chip", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("applies the tone class for a known tone", () => {
    const element = createElement("c-status-chip", { is: StatusChip });
    element.tone = "success";
    element.label = "Active";
    document.body.appendChild(element);

    const chip = element.shadowRoot.querySelector('[data-id="chip"], .chip');
    expect(chip.className).toBe("chip chip_success");
  });

  it("falls back to neutral for an unknown tone", () => {
    const element = createElement("c-status-chip", { is: StatusChip });
    element.tone = "sparkly";
    element.label = "Mystery";
    document.body.appendChild(element);

    const chip = element.shadowRoot.querySelector(".chip");
    expect(chip.className).toBe("chip chip_neutral");
  });

  it.each([
    ["success", "utility:check"],
    ["warning", "utility:warning"],
    ["error", "utility:error"],
    ["info", "utility:info"],
    ["neutral", "utility:dash"]
  ])("uses the default icon for tone %s", (tone, expectedIcon) => {
    const element = createElement("c-status-chip", { is: StatusChip });
    element.tone = tone;
    element.label = "Status";
    document.body.appendChild(element);

    const icon = element.shadowRoot.querySelector("lightning-icon");
    expect(icon.iconName).toBe(expectedIcon);
  });

  it("lets iconName override the default icon", () => {
    const element = createElement("c-status-chip", { is: StatusChip });
    element.tone = "success";
    element.label = "Active";
    element.iconName = "utility:custom";
    document.body.appendChild(element);

    const icon = element.shadowRoot.querySelector("lightning-icon");
    expect(icon.iconName).toBe("utility:custom");
  });

  it("sets the title to the label", () => {
    const element = createElement("c-status-chip", { is: StatusChip });
    element.tone = "info";
    element.label = "In review";
    document.body.appendChild(element);

    const chip = element.shadowRoot.querySelector(".chip");
    expect(chip.title).toBe("In review");
  });
});
