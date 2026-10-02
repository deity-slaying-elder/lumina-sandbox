import LightningDatatable from "lightning/datatable";
import statusChipCell from "./statusChipCell.html";
import coverageCell from "./coverageCell.html";
import facilityCell from "./facilityCell.html";

/**
 * The worklist datatable, with two cell types the base component does not ship.
 *
 * Both render c/statusChip, so a status reads the same here as it does anywhere
 * else in the app rather than being plain text in one place and a chip in another.
 */
export default class SchedulingDatatable extends LightningDatatable {
  static customTypes = {
    // Facility name over its parent company. Parent company had a column of its own
    // that was blank on most rows and twelve rem wide; here it costs nothing.
    facility: {
      template: facilityCell,
      standardCellLayout: true,
      typeAttributes: ["name", "parent", "url"]
    },
    // The facility's own status: Onboarding, Opportunity, and so on.
    statusChip: {
      template: statusChipCell,
      standardCellLayout: true,
      typeAttributes: ["tone"]
    },
    // Whether the facility has an event on the calendar yet. A facility with
    // none is the thing this screen exists to surface, so it is a chip rather
    // than a zero the eye slides past.
    coverage: {
      template: coverageCell,
      standardCellLayout: true,
      typeAttributes: ["label", "tone", "iconName", "detail"]
    }
  };
}
