public with sharing class UploadLongevityFileController {

    public class InvocableRequest {
        @InvocableVariable(required=true)
        public List<String> contentVersionsCollection;
    }

    public class ProcessingResult {
        public Integer totalRows;
        public Integer matchedPatients;
        public Integer updatedPatients;
        public Integer alreadyMarked;
        public Integer notFound;
        public List<String> errors;

        public ProcessingResult() {
            this.totalRows = 0;
            this.matchedPatients = 0;
            this.updatedPatients = 0;
            this.alreadyMarked = 0;
            this.notFound = 0;
            this.errors = new List<String>();
        }
    }

    @InvocableMethod(label='Process Longevity Upload File' description='Process CSV/Excel file to mark patients as Longevity based on Medicare ID')
    public static List<String> processFile(List<InvocableRequest> requests) {
        List<String> responses = new List<String>();

        try {
            String contentVersionId = null;
            for (InvocableRequest request : requests) {
                if (request.contentVersionsCollection != null && !request.contentVersionsCollection.isEmpty()) {
                    contentVersionId = request.contentVersionsCollection[0];
                }
            }

            if (String.isBlank(contentVersionId)) {
                responses.add('Error: No file provided');
                return responses;
            }

            // Get the file content
            String fileContent = getFileContent(contentVersionId);

            if (String.isBlank(fileContent)) {
                responses.add('Error: Could not read file content');
                return responses;
            }

            // Parse the CSV and process
            ProcessingResult result = processCSVContent(fileContent);

            // Build response message
            if (!result.errors.isEmpty()) {
                responses.add(String.join(result.errors, '; '));
            } else {
                String responseMessage = 'Upload Successful. ' +
                    'Total Rows: ' + result.totalRows + ', ' +
                    'Patients Updated: ' + result.updatedPatients + ', ' +
                    'Already Marked: ' + result.alreadyMarked + ', ' +
                    'Not Found: ' + result.notFound;
                responses.add(responseMessage);
            }

        } catch (Exception e) {
            System.debug('Error processing longevity file: ' + e.getMessage());
            System.debug('Stack trace: ' + e.getStackTraceString());
            responses.add('Error: ' + e.getMessage());
        }

        return responses;
    }

    private static String getFileContent(Id contentVersionId) {
        try {
            ContentVersion contentVersion = [
                SELECT VersionData, FileExtension
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

            if (contentVersion != null && contentVersion.VersionData != null) {
                return contentVersion.VersionData.toString();
            }
        } catch (Exception e) {
            System.debug('Error reading file: ' + e.getMessage());
        }

        return null;
    }

    @TestVisible
    private static ProcessingResult processCSVContent(String csvContent) {
        ProcessingResult result = new ProcessingResult();

        // Parse CSV rows
        List<List<String>> rows = parseCSV(csvContent);

        if (rows.isEmpty()) {
            result.errors.add('No data found in file');
            return result;
        }

        // Find the Medicare ID column index
        List<String> headers = rows[0];
        Integer medicareIdIndex = -1;

        for (Integer i = 0; i < headers.size(); i++) {
            String header = headers[i].trim().toLowerCase().replaceAll('[^a-z0-9]', '');
            if (header == 'medicareid' || header == 'medicare' || header == 'medicarenumber') {
                medicareIdIndex = i;
                break;
            }
        }

        if (medicareIdIndex == -1) {
            result.errors.add('Medicare ID column not found. Please ensure the file has a column named "Medicare ID"');
            return result;
        }

        // Collect all Medicare IDs from the file (skip header row)
        Set<String> medicareIds = new Set<String>();
        for (Integer i = 1; i < rows.size(); i++) {
            List<String> row = rows[i];
            if (row.size() > medicareIdIndex) {
                String medicareId = row[medicareIdIndex].trim();
                if (String.isNotBlank(medicareId)) {
                    medicareIds.add(medicareId);
                    result.totalRows++;
                }
            }
        }

        if (medicareIds.isEmpty()) {
            result.errors.add('No Medicare IDs found in file');
            return result;
        }

        // Query patients matching the Medicare IDs
        Map<String, Patient__c> patientsByMedicareId = new Map<String, Patient__c>();
        for (Patient__c patient : [
            SELECT Id, Medicare__c, Longevity__c
            FROM Patient__c
            WHERE Medicare__c IN :medicareIds
        ]) {
            patientsByMedicareId.put(patient.Medicare__c, patient);
        }

        // Process and update patients
        List<Patient__c> patientsToUpdate = new List<Patient__c>();

        for (String medicareId : medicareIds) {
            Patient__c patient = patientsByMedicareId.get(medicareId);

            if (patient == null) {
                result.notFound++;
            } else {
                result.matchedPatients++;

                if (patient.Longevity__c == true) {
                    result.alreadyMarked++;
                } else {
                    patient.Longevity__c = true;
                    patientsToUpdate.add(patient);
                }
            }
        }

        // Update patients
        if (!patientsToUpdate.isEmpty()) {
            try {
                update patientsToUpdate;
                result.updatedPatients = patientsToUpdate.size();
            } catch (DmlException e) {
                result.errors.add('Error updating patients: ' + e.getMessage());
            }
        }

        return result;
    }

    @TestVisible
    private static List<List<String>> parseCSV(String csvContent) {
        List<List<String>> rows = new List<List<String>>();

        if (String.isBlank(csvContent)) {
            return rows;
        }

        // Normalize line endings
        csvContent = csvContent.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

        // Split into lines
        List<String> lines = csvContent.split('\n');

        for (String line : lines) {
            if (String.isNotBlank(line)) {
                List<String> values = parseCSVLine(line);
                if (!values.isEmpty()) {
                    rows.add(values);
                }
            }
        }

        return rows;
    }

    @TestVisible
    private static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();

        if (String.isBlank(line)) {
            return values;
        }

        Boolean inQuotes = false;
        String currentValue = '';

        for (Integer i = 0; i < line.length(); i++) {
            String c = line.substring(i, i + 1);

            if (c == '"') {
                inQuotes = !inQuotes;
            } else if (c == ',' && !inQuotes) {
                values.add(currentValue.trim());
                currentValue = '';
            } else {
                currentValue += c;
            }
        }

        // Add the last value
        values.add(currentValue.trim());

        return values;
    }
}