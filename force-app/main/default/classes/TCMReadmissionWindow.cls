/**
 * Reporting window for the daily readmission email, resolved in the configured business
 * timezone.
 *
 * Monday covers Friday, Saturday and Sunday (Friday 00:00 through Monday 00:00). Every
 * other day covers the single previous day.
 *
 * Bounds are exposed as UTC Datetimes rather than as SOQL date literals. Admit_DateTime__c
 * is an absolute instant, and a literal like YESTERDAY would resolve against the running
 * user's timezone -- which for scheduled Apex is whoever happened to schedule the job, not
 * a business decision.
 */
public with sharing class TCMReadmissionWindow {

    private static final String DEFAULT_TZ = 'America/New_York';

    /** 1900-01-01 was a Monday. Used to derive weekday without locale-dependent formatting. */
    private static final Date REFERENCE_MONDAY = Date.newInstance(1900, 1, 1);

    public final String timeZoneName;
    public final Date localStartDate;
    public final Date localEndDate;
    public final Datetime startUtc;
    public final Datetime endUtc;

    public TCMReadmissionWindow(String tzName) {
        this(tzName, Datetime.now());
    }

    @TestVisible
    private TCMReadmissionWindow(String tzName, Datetime nowUtc) {
        this.timeZoneName = String.isBlank(tzName) ? DEFAULT_TZ : tzName.trim();
        TimeZone tz = TimeZone.getTimeZone(this.timeZoneName);

        Date localToday = Date.valueOf(nowUtc.format('yyyy-MM-dd', this.timeZoneName));

        this.localEndDate = localToday;
        this.localStartDate = localToday.addDays(isMonday(localToday) ? -3 : -1);
        this.startUtc = toUtcStartOfDay(this.localStartDate, tz);
        this.endUtc = toUtcStartOfDay(this.localEndDate, tz);
    }

    /**
     * The window whose last covered day is the given local date.
     *
     * Used by the report page, which is rendered in its own request and must not be handed a
     * start and end it simply trusts. It receives a report date and derives the same window the
     * job would have derived for that date, so a caller cannot widen the range.
     */
    public static TCMReadmissionWindow forLastCoveredDate(String tzName, Date lastCovered) {
        if (lastCovered == null) {
            return new TCMReadmissionWindow(tzName);
        }
        // localEndDate is exclusive, so the day after the last covered day anchors the window.
        Date anchor = lastCovered.addDays(1);
        return new TCMReadmissionWindow(
            tzName,
            Datetime.newInstanceGmt(anchor, Time.newInstance(12, 0, 0, 0))
        );
    }

    /** Number of calendar days covered: 3 on Monday, otherwise 1. */
    public Integer dayCount() {
        return localStartDate.daysBetween(localEndDate);
    }

    /** Last full day in the window, which is what the filename and subject refer to. */
    public Date lastCoveredDate() {
        return localEndDate.addDays(-1);
    }

    public String fileDateToken() {
        return isoDate(lastCoveredDate());
    }

    /** Human-readable window for the email body. */
    public String describe() {
        if (dayCount() <= 1) {
            return longDate(localStartDate);
        }
        return longDate(localStartDate) + ' through ' + longDate(lastCoveredDate());
    }

    private static Boolean isMonday(Date value) {
        return Math.mod(REFERENCE_MONDAY.daysBetween(value), 7) == 0;
    }

    private static String isoDate(Date value) {
        return Datetime.newInstanceGmt(value, Time.newInstance(0, 0, 0, 0)).formatGmt('yyyy-MM-dd');
    }

    private static String longDate(Date value) {
        return Datetime.newInstanceGmt(value, Time.newInstance(0, 0, 0, 0)).formatGmt('EEEE, MMMM d, yyyy');
    }

    /**
     * Converts local midnight to the equivalent UTC instant.
     *
     * getOffset() needs an instant, so the first pass treats local midnight as if it were
     * GMT -- within a day of the true instant. Re-deriving the offset at the corrected
     * instant handles the case where a DST transition falls between the two.
     */
    private static Datetime toUtcStartOfDay(Date localDate, TimeZone tz) {
        Datetime asIfGmt = Datetime.newInstanceGmt(localDate, Time.newInstance(0, 0, 0, 0));
        Integer offsetMs = tz.getOffset(asIfGmt);
        Datetime firstPass = asIfGmt.addSeconds(-offsetMs / 1000);
        Integer correctedMs = tz.getOffset(firstPass);
        return correctedMs == offsetMs ? firstPass : asIfGmt.addSeconds(-correctedMs / 1000);
    }
}