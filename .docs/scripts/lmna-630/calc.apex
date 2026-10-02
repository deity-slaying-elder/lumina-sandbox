// Populate the three new rollups across every existing facility. DLRS realtime only
// maintains them from the next Patient DML onwards, so the back-fill is explicit.
for (String rollup : new List<String>{ 'Facility_Census', 'Facility_Seen', 'Facility_Consented' }) {
  Id jobId = dlrs.RollupService.runJobToCalculate(rollup);
  System.debug(LoggingLevel.ERROR, 'QUEUED ' + rollup + ' -> ' + jobId);
}
