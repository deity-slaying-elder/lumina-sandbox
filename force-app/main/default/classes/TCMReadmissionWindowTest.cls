/**
 * Weekday and DST behaviour of the reporting window.
 *
 * Anchor dates used below, verified against the calendar:
 *   2026-08-17 Monday      2026-08-19 Wednesday
 *   2026-01-14 Wednesday   2026-03-09 Monday (DST began Sunday 2026-03-08)
 */
@IsTest
private class TCMReadmissionWindowTest {

    private static final String ET = 'America/New_York';

    @IsTest
    static void nonMondayCoversThePreviousDayOnly() {
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 19, 12, 0, 0)
        );

        System.assertEquals(Date.newInstance(2026, 8, 18), w.localStartDate, 'start is the previous day');
        System.assertEquals(Date.newInstance(2026, 8, 19), w.localEndDate, 'end is today, exclusive');
        System.assertEquals(1, w.dayCount(), 'a midweek run covers one day');
        System.assertEquals(Date.newInstance(2026, 8, 18), w.lastCoveredDate());
        // EDT is UTC-4 in August.
        System.assertEquals(Datetime.newInstanceGmt(2026, 8, 18, 4, 0, 0), w.startUtc);
        System.assertEquals(Datetime.newInstanceGmt(2026, 8, 19, 4, 0, 0), w.endUtc);
    }

    @IsTest
    static void mondayCoversFridaySaturdayAndSunday() {
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 17, 12, 0, 0)
        );

        System.assertEquals(Date.newInstance(2026, 8, 14), w.localStartDate, 'Monday reaches back to Friday');
        System.assertEquals(Date.newInstance(2026, 8, 17), w.localEndDate);
        System.assertEquals(3, w.dayCount(), 'Friday, Saturday and Sunday');
        System.assertEquals(Date.newInstance(2026, 8, 16), w.lastCoveredDate(), 'last covered day is Sunday');
        System.assertEquals(Datetime.newInstanceGmt(2026, 8, 14, 4, 0, 0), w.startUtc);
        System.assertEquals(Datetime.newInstanceGmt(2026, 8, 17, 4, 0, 0), w.endUtc);
    }

    @IsTest
    static void standardTimeUsesAFiveHourOffset() {
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 1, 14, 12, 0, 0)
        );

        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 13, 5, 0, 0), w.startUtc, 'EST is UTC-5');
        System.assertEquals(Datetime.newInstanceGmt(2026, 1, 14, 5, 0, 0), w.endUtc);
    }

    @IsTest
    static void mondayWindowSpanningDstStartUsesTheRightOffsetAtEachEnd() {
        // Friday opens in EST, Monday closes in EDT. A single fixed offset would put one
        // bound an hour wrong and silently include or drop an hour of admissions.
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 3, 9, 12, 0, 0)
        );

        System.assertEquals(Date.newInstance(2026, 3, 6), w.localStartDate);
        System.assertEquals(3, w.dayCount());
        System.assertEquals(Datetime.newInstanceGmt(2026, 3, 6, 5, 0, 0), w.startUtc, 'Friday is still EST');
        System.assertEquals(Datetime.newInstanceGmt(2026, 3, 9, 4, 0, 0), w.endUtc, 'Monday is EDT');
    }

    @IsTest
    static void lateUtcEveningStillResolvesToTheEasternCalendarDay() {
        // 2026-08-19T02:00Z is still 2026-08-18 22:00 ET, so "yesterday" is the 17th.
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 19, 2, 0, 0)
        );

        System.assertEquals(Date.newInstance(2026, 8, 18), w.localEndDate, 'local date is still the 18th');
        System.assertEquals(Date.newInstance(2026, 8, 17), w.localStartDate);
    }

    @IsTest
    static void publicConstructorResolvesAgainstTheCurrentTime() {
        // The single-argument constructor is the one the batch actually uses, so it needs
        // covering even though the assertions have to stay relative.
        TCMReadmissionWindow w = new TCMReadmissionWindow(ET);

        System.assertEquals(ET, w.timeZoneName);
        System.assert(w.dayCount() == 1 || w.dayCount() == 3, 'unexpected span: ' + w.dayCount());
        System.assert(w.startUtc < w.endUtc, 'window must be ordered');
        System.assert(w.endUtc <= Datetime.now(), 'the window must not extend into the future');
        System.assertEquals(w.localEndDate.addDays(-1), w.lastCoveredDate());
    }

    @IsTest
    static void blankTimezoneFallsBackToEastern() {
        TCMReadmissionWindow w = new TCMReadmissionWindow(
            null, Datetime.newInstanceGmt(2026, 8, 19, 12, 0, 0)
        );

        System.assertEquals(ET, w.timeZoneName);
    }

    @IsTest
    static void describeAndFileTokenReflectTheWindowLength() {
        TCMReadmissionWindow single = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 19, 12, 0, 0)
        );
        System.assertEquals('2026-08-18', single.fileDateToken());
        System.assert(
            !single.describe().contains('through'),
            'a one-day window should read as a single date, got: ' + single.describe()
        );

        TCMReadmissionWindow monday = new TCMReadmissionWindow(
            ET, Datetime.newInstanceGmt(2026, 8, 17, 12, 0, 0)
        );
        System.assertEquals('2026-08-16', monday.fileDateToken(), 'token is the last covered day');
        System.assert(
            monday.describe().contains('through'),
            'a three-day window should read as a range, got: ' + monday.describe()
        );
    }
}