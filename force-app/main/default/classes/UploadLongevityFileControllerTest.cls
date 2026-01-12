@isTest
private class UploadLongevityFileControllerTest {

    @TestSetup
    static void setupTestData() {
        // Create test patients with Medicare IDs
        List<Patient__c> patients = new List<Patient__c>();

        // Patient that will be updated (Longevity = false)
        patients.add(new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient1',
            Status__c = 'Active',
            Medicare__c = 'MED001',
            Longevity__c = false
        ));

        // Patient already marked as Longevity
        patients.add(new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient2',
            Status__c = 'Active',
            Medicare__c = 'MED002',
            Longevity__c = true
        ));

        // Another patient to update
        patients.add(new Patient__c(
            First_Name__c = 'Test',
            Last_Name__c = 'Patient3',
            Status__c = 'Active',
            Medicare__c = 'MED003',
            Longevity__c = false
        ));

        insert patients;
    }

    @isTest
    static void testProcessFile_Success() {
        // Create CSV content
        String csvContent = 'Name,Medicare ID,Other Column\n' +
                           'Patient 1,MED001,Value1\n' +
                           'Patient 2,MED002,Value2\n' +
                           'Patient 3,MED003,Value3';

        // Create ContentVersion
        ContentVersion cv = new ContentVersion(
            Title = 'Test Longevity File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        // Query to get the ID
        cv = [SELECT Id FROM ContentVersion WHERE Id = :cv.Id LIMIT 1];

        // Create request
        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        // Verify results
        System.assertEquals(1, results.size(), 'Should return one result');
        System.assert(results[0].contains('Upload Successful'), 'Should contain success message');
        System.assert(results[0].contains('Patients Updated: 2'), 'Should update 2 patients');
        System.assert(results[0].contains('Already Marked: 1'), 'Should have 1 already marked');

        // Verify patient records were updated
        List<Patient__c> updatedPatients = [SELECT Medicare__c, Longevity__c FROM Patient__c WHERE Medicare__c IN ('MED001', 'MED002', 'MED003')];
        for (Patient__c p : updatedPatients) {
            System.assertEquals(true, p.Longevity__c, 'All patients should have Longevity = true');
        }
    }

    @isTest
    static void testProcessFile_NoFileProvided() {
        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>();

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assert(results[0].contains('Error: No file provided'), 'Should return no file error');
    }

    @isTest
    static void testProcessFile_NullContentVersionsCollection() {
        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = null;

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return one result');
        System.assert(results[0].contains('Error: No file provided'), 'Should return no file error');
    }

    @isTest
    static void testProcessFile_MedicareColumnNotFound() {
        // Create CSV without Medicare ID column
        String csvContent = 'Name,Other Column\n' +
                           'Patient 1,Value1';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Medicare ID column not found'), 'Should return column not found error');
    }

    @isTest
    static void testProcessFile_PatientNotFound() {
        // Create CSV with Medicare IDs that don't exist
        String csvContent = 'Medicare ID\n' +
                           'NOTEXIST001\n' +
                           'NOTEXIST002';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Not Found: 2'), 'Should report 2 not found');
    }

    @isTest
    static void testProcessFile_EmptyFile() {
        // Use whitespace-only content since Blob.valueOf('') returns null
        String csvContent = '   ';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Error') || results[0].contains('No data'), 'Should handle empty file');
    }

    @isTest
    static void testProcessFile_HeaderOnlyFile() {
        String csvContent = 'Medicare ID,Name';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('No Medicare IDs found'), 'Should report no Medicare IDs');
    }

    @isTest
    static void testProcessFile_QuotedValues() {
        // Test CSV with quoted values
        String csvContent = 'Name,"Medicare ID",Notes\n' +
                           '"Patient, First",MED001,"Some notes"';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Upload Successful'), 'Should process quoted values');
    }

    @isTest
    static void testProcessFile_AlternateColumnNames() {
        // Test with "Medicare" instead of "Medicare ID"
        String csvContent = 'Name,Medicare,Notes\n' +
                           'Patient 1,MED001,Notes';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Upload Successful'), 'Should recognize alternate column name');
    }

    @isTest
    static void testProcessFile_WindowsLineEndings() {
        // Test with Windows line endings (CRLF)
        String csvContent = 'Medicare ID\r\nMED001\r\nMED002';

        ContentVersion cv = new ContentVersion(
            Title = 'Test File',
            PathOnClient = 'test.csv',
            VersionData = Blob.valueOf(csvContent)
        );
        insert cv;

        UploadLongevityFileController.InvocableRequest request = new UploadLongevityFileController.InvocableRequest();
        request.contentVersionsCollection = new List<String>{ cv.Id };

        Test.startTest();
        List<String> results = UploadLongevityFileController.processFile(new List<UploadLongevityFileController.InvocableRequest>{ request });
        Test.stopTest();

        System.assert(results[0].contains('Upload Successful'), 'Should handle Windows line endings');
    }

    @isTest
    static void testProcessCSVContent_DirectCall() {
        String csvContent = 'Medicare ID\nMED001\nMED002';

        Test.startTest();
        UploadLongevityFileController.ProcessingResult result = UploadLongevityFileController.processCSVContent(csvContent);
        Test.stopTest();

        System.assertEquals(2, result.totalRows, 'Should count 2 rows');
    }

    @isTest
    static void testParseCSV_DirectCall() {
        String csvContent = 'Col1,Col2\nVal1,Val2';

        Test.startTest();
        List<List<String>> rows = UploadLongevityFileController.parseCSV(csvContent);
        Test.stopTest();

        System.assertEquals(2, rows.size(), 'Should have 2 rows');
        System.assertEquals(2, rows[0].size(), 'First row should have 2 columns');
    }

    @isTest
    static void testParseCSVLine_DirectCall() {
        String line = 'Value1,Value2,Value3';

        Test.startTest();
        List<String> values = UploadLongevityFileController.parseCSVLine(line);
        Test.stopTest();

        System.assertEquals(3, values.size(), 'Should have 3 values');
        System.assertEquals('Value1', values[0], 'First value should be Value1');
    }

    @isTest
    static void testParseCSVLine_EmptyLine() {
        Test.startTest();
        List<String> values = UploadLongevityFileController.parseCSVLine('');
        Test.stopTest();

        System.assertEquals(0, values.size(), 'Should return empty list for empty line');
    }

    @isTest
    static void testParseCSV_NullContent() {
        Test.startTest();
        List<List<String>> rows = UploadLongevityFileController.parseCSV(null);
        Test.stopTest();

        System.assertEquals(0, rows.size(), 'Should return empty list for null content');
    }

    @isTest
    static void testProcessingResultConstructor() {
        Test.startTest();
        UploadLongevityFileController.ProcessingResult result = new UploadLongevityFileController.ProcessingResult();
        Test.stopTest();

        System.assertEquals(0, result.totalRows, 'totalRows should initialize to 0');
        System.assertEquals(0, result.matchedPatients, 'matchedPatients should initialize to 0');
        System.assertEquals(0, result.updatedPatients, 'updatedPatients should initialize to 0');
        System.assertEquals(0, result.alreadyMarked, 'alreadyMarked should initialize to 0');
        System.assertEquals(0, result.notFound, 'notFound should initialize to 0');
        System.assertNotEquals(null, result.errors, 'errors list should be initialized');
    }
}