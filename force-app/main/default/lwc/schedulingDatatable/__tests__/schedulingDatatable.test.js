import SchedulingDatatable from "c/schedulingDatatable";

describe("c-scheduling-datatable", () => {
  it("registers the two cell types the worklist needs", () => {
    const types = SchedulingDatatable.customTypes;
    expect(Object.keys(types).sort()).toEqual([
      "coverage",
      "facility",
      "statusChip"
    ]);
  });

  it("keeps the standard cell layout so rows line up with the base table", () => {
    const types = SchedulingDatatable.customTypes;
    expect(types.statusChip.standardCellLayout).toBe(true);
    expect(types.coverage.standardCellLayout).toBe(true);
    expect(types.facility.standardCellLayout).toBe(true);
  });

  it("accepts the attributes the columns pass through", () => {
    const types = SchedulingDatatable.customTypes;
    expect(types.statusChip.typeAttributes).toEqual(["tone"]);
    expect(types.coverage.typeAttributes).toEqual([
      "label",
      "tone",
      "iconName",
      "detail"
    ]);
    expect(types.facility.typeAttributes).toEqual(["name", "parent", "url"]);
  });
});
