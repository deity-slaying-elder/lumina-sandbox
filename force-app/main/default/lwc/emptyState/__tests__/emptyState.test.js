import { createElement } from "lwc";
import EmptyState from "c/emptyState";

describe("c-empty-state", () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it("uses role alert for the failed variant", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.variant = "failed";
    element.heading = "Load failed";
    element.body = "Sample data could not load.";
    document.body.appendChild(element);

    const root = element.shadowRoot.querySelector(".empty");
    expect(root.getAttribute("role")).toBe("alert");
  });

  it("uses role status for non-failed variants", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.variant = "first-use";
    element.heading = "Nothing here yet";
    element.body = "Create your first sample record.";
    document.body.appendChild(element);

    const root = element.shadowRoot.querySelector(".empty");
    expect(root.getAttribute("role")).toBe("status");
  });

  it("fires primaryaction when the primary button is clicked", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.heading = "Nothing here yet";
    element.body = "Create your first sample record.";
    element.ctaLabel = "Create record";
    const handler = jest.fn();
    element.addEventListener("primaryaction", handler);
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const button = element.shadowRoot.querySelector(
        '[data-id="primary-action"]'
      );
      button.click();
      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  it("fires secondaryaction when the secondary button is clicked", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.heading = "No matches";
    element.body = "Try clearing filters.";
    element.secondaryLabel = "Clear filters";
    const handler = jest.fn();
    element.addEventListener("secondaryaction", handler);
    document.body.appendChild(element);

    return Promise.resolve().then(() => {
      const button = element.shadowRoot.querySelector(
        '[data-id="secondary-action"]'
      );
      button.click();
      expect(handler).toHaveBeenCalledTimes(1);
    });
  });

  it("hides the buttons when their labels are not set", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.heading = "Nothing here yet";
    element.body = "Create your first sample record.";
    document.body.appendChild(element);

    expect(
      element.shadowRoot.querySelector('[data-id="primary-action"]')
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="secondary-action"]')
    ).toBeNull();
  });

  it("shows the reference line only for the failed variant", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.variant = "failed";
    element.heading = "Load failed";
    element.body = "Sample data could not load.";
    element.reference = "REF-1234";
    document.body.appendChild(element);

    const ref = element.shadowRoot.querySelector(".empty__ref");
    expect(ref.textContent).toBe("Reference REF-1234");
  });

  it("omits the reference line for non-failed variants even with a reference set", () => {
    const element = createElement("c-empty-state", { is: EmptyState });
    element.variant = "filtered";
    element.heading = "No matches";
    element.body = "Try clearing filters.";
    element.reference = "REF-1234";
    document.body.appendChild(element);

    expect(element.shadowRoot.querySelector(".empty__ref")).toBeNull();
  });
});
