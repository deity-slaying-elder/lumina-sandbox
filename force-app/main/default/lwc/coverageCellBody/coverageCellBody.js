import { LightningElement, api } from "lwc";

/**
 * The scheduled-coverage cell's contents, as its own component, for the same reason
 * as the facility cell: a custom datatable cell template cannot be styled from the
 * datatable subclass.
 */
export default class CoverageCellBody extends LightningElement {
  @api label;
  @api tone;
  @api iconName;
  @api detail;
}
