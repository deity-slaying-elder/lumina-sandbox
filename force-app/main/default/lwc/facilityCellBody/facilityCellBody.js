import { LightningElement, api } from "lwc";

/**
 * The facility cell's contents, as its own component.
 *
 * A custom lightning-datatable cell template renders inside the BASE datatable's
 * shadow tree, not the subclass's, so a stylesheet on the subclass never reaches it.
 * Giving the cell its own component is what lets it carry its own CSS.
 */
export default class FacilityCellBody extends LightningElement {
  @api name;
  @api parent;
  @api url;
}
