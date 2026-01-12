import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFacilitiesAndFields from '@salesforce/apex/FacilityEditorController.getFacilitiesAndFields';
import updateFacilities from '@salesforce/apex/FacilityEditorController.updateFacilities';

export default class FacilityEditor extends LightningElement {
    @track columns = [];
    @track allData = [];
    @track filteredData = [];
    @track selectedFacilities = [];
    @track searchTerm = '';
    @track draftChanges = new Map();
    @track rowsWithChanges = new Set();

    fields = [];
    picklistOptionsMap = {};
    isLoading = true;
    errorMessage = '';

    _recordId;
    _dataLoaded = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadData();
        }
    }

    connectedCallback() {
        if (this._recordId && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadData();
        }
    }

    loadData() {
        if (!this._recordId) {
            this.errorMessage = 'No Account ID available. Please ensure this component is used on an Account page.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        getFacilitiesAndFields({ accountId: this._recordId })
            .then(result => {
                console.error('=== FACILITY EDITOR DEBUG ===');
                console.error('Raw result from Apex:', JSON.stringify(result, null, 2));

                if (!result || !result.fields || !result.facilities) {
                    throw new Error('Invalid response structure from server');
                }

                this.fields = result.fields;

                // Extract picklist values from field metadata
                this.fields.forEach(field => {
                    if (field.type.toLowerCase() === 'picklist' && field.picklistValues) {
                        this.picklistOptionsMap[field.fieldPath] = field.picklistValues;
                    }
                });

                this.columns = this.buildColumns(result.fields);
                this.allData = this.buildTableData(result.facilities);
                this.filteredData = [...this.allData];

                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading data:', error);
                let errorMsg = this.getErrorMessage(error);

                if (errorMsg.includes("doesn't have any facilities") ||
                    errorMsg.includes("No facilities") ||
                    errorMsg.includes("Script-thrown exception")) {
                    this.errorMessage = "There are no facilities linked to this account yet.";
                } else {
                    this.errorMessage = errorMsg;
                }

                this.isLoading = false;
            });
    }

    buildColumns(fields) {
        const columns = [
            {
                label: 'Facility Name',
                fieldName: 'Name',
                displayField: 'Name',
                type: 'text',
                editable: false,
                isLink: true,
                linkField: 'facilityUrl',
                inputType: 'text',
                isPicklist: false
            }
        ];

        fields.forEach(field => {
            const type = field.type.toLowerCase();
            let inputType = 'text';
            let isPicklist = false;

            if (type === 'boolean') {
                inputType = 'checkbox';
            } else if (type === 'currency') {
                inputType = 'number';
            } else if (type === 'percent') {
                inputType = 'number';
            } else if (type === 'date') {
                inputType = 'date';
            } else if (type === 'datetime') {
                inputType = 'datetime-local';
            } else if (type === 'double' || type === 'integer') {
                inputType = 'number';
            } else if (type === 'picklist') {
                isPicklist = true;
                inputType = 'text';
            }

            const column = {
                label: field.label,
                fieldName: field.fieldPath,
                displayField: field.fieldPath,
                type: type,
                editable: field.updateable || type === 'picklist',
                inputType: inputType,
                isPicklist: isPicklist,
                optionsField: isPicklist ? field.fieldPath + 'Options' : null
            };

            if (type === 'picklist' && field.picklistValues) {
                column.picklistValues = field.picklistValues;
            }

            columns.push(column);
        });

        return columns;
    }

    buildTableData(facilities) {
        const data = [];
        let rowNumber = 1;

        console.log('Building table data, facilities:', JSON.stringify(facilities));
        console.log('Fields:', JSON.stringify(this.fields));

        facilities.forEach(facility => {
            // Store original values for change detection
            const originalValues = {};
            this.fields.forEach(field => {
                originalValues[field.fieldPath] = facility[field.fieldPath];
                console.error(`Field ${field.fieldPath} = ${facility[field.fieldPath]} (type: ${typeof facility[field.fieldPath]})`);
            });

            const row = {
                Id: facility.Id,
                Name: facility.Name,
                facilityUrl: `/${facility.Id}`,
                originalValues: originalValues,
                rowNumber: rowNumber++,
                isSelected: this.selectedFacilities.includes(facility.Id),
                ...this.getFieldValues(facility)
            };

            // Add picklist options to each row
            this.fields.forEach(field => {
                if (field.type.toLowerCase() === 'picklist' && field.picklistValues) {
                    row[field.fieldPath + 'Options'] = field.picklistValues;
                }
            });

            // Pre-compute cell values
            row.cells = this.columns.map(col => ({
                columnKey: col.fieldName,
                value: row[col.fieldName],
                displayValue: row[col.displayField] || row[col.fieldName],
                linkValue: col.isLink ? row[col.linkField] : null,
                optionsValue: col.isPicklist ? row[col.optionsField] : null,
                isPicklist: col.isPicklist,
                isLink: col.isLink,
                editable: col.editable,
                inputType: col.inputType,
                isCheckbox: col.inputType === 'checkbox',
                label: col.label
            }));

            data.push(row);
        });

        return data;
    }

    getFieldValues(facility) {
        const values = {};
        this.fields.forEach(field => {
            values[field.fieldPath] = facility[field.fieldPath];
        });
        return values;
    }

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.filterData();
    }

    filterData() {
        this.filteredData = this.allData
            .filter(row => {
                const searchMatch = !this.searchTerm ||
                    row.Name.toLowerCase().includes(this.searchTerm.toLowerCase());
                return searchMatch;
            })
            .map(row => {
                const displayRow = { ...row };

                // Apply any pending draft changes
                if (this.draftChanges.has(row.Id)) {
                    const changes = this.draftChanges.get(row.Id);
                    Object.keys(changes).forEach(fieldName => {
                        displayRow[fieldName] = changes[fieldName];
                    });
                }

                // Rebuild cells array
                displayRow.cells = this.columns.map(col => ({
                    columnKey: col.fieldName,
                    value: displayRow[col.fieldName],
                    displayValue: displayRow[col.displayField] || displayRow[col.fieldName],
                    linkValue: col.isLink ? displayRow[col.linkField] : null,
                    optionsValue: col.isPicklist ? displayRow[col.optionsField] : null,
                    isPicklist: col.isPicklist,
                    isLink: col.isLink,
                    editable: col.editable,
                    inputType: col.inputType,
                    isCheckbox: col.inputType === 'checkbox',
                    label: col.label
                }));

                return displayRow;
            });
    }

    handleFieldChange(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        // Handle checkbox values differently - they use checked property, not detail.value
        const isCheckbox = event.target.type === 'checkbox';
        const newValue = isCheckbox ? event.target.checked : event.detail.value;

        // If there are selected facilities, apply changes to all selected
        if (this.selectedFacilities.length > 1 && this.selectedFacilities.includes(rowId)) {
            this.selectedFacilities.forEach(selectedRowId => {
                if (!this.draftChanges.has(selectedRowId)) {
                    this.draftChanges.set(selectedRowId, {});
                }
                this.draftChanges.get(selectedRowId)[fieldName] = newValue;
                this.rowsWithChanges.add(selectedRowId);
            });
            this.showToast('Success', `${fieldName} updated for ${this.selectedFacilities.length} selected facilities. Click "Update Facilities" to save.`, 'success');
        } else {
            // Update only the edited row
            if (!this.draftChanges.has(rowId)) {
                this.draftChanges.set(rowId, {});
            }
            this.draftChanges.get(rowId)[fieldName] = newValue;
            this.rowsWithChanges.add(rowId);
        }

        this.filterData();
    }

    handleRowSelect(event) {
        const rowId = event.target.dataset.id;
        const isChecked = event.target.checked;

        if (isChecked) {
            if (!this.selectedFacilities.includes(rowId)) {
                this.selectedFacilities = [...this.selectedFacilities, rowId];
            }
        } else {
            this.selectedFacilities = this.selectedFacilities.filter(id => id !== rowId);
        }

        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: this.selectedFacilities.includes(row.Id)
        }));

        this.filterData();
    }

    handleSelectAllRows(event) {
        const isChecked = event.target.checked;

        if (isChecked) {
            this.selectedFacilities = this.filteredData.map(row => row.Id);
        } else {
            this.selectedFacilities = [];
        }

        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: this.selectedFacilities.includes(row.Id)
        }));

        this.filterData();
    }

    handleCancelChanges() {
        this.draftChanges.clear();
        this.rowsWithChanges.clear();
        this.selectedFacilities = [];

        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: false
        }));

        this.filterData();
        this.showToast('Info', 'All pending changes have been discarded.', 'info');
    }

    handleUpdateFacilities() {
        const facilitiesToUpdate = this.buildUpdateData();

        if (facilitiesToUpdate.length === 0) {
            this.showToast('Info', 'No changes detected. Please modify at least one field to update.', 'info');
            return;
        }

        this.isLoading = true;

        updateFacilities({ facilitiesJson: JSON.stringify(facilitiesToUpdate) })
            .then(result => {
                this.showToast('Success', `${result.count} facilities updated successfully!`, 'success');
                this.isLoading = false;

                this.draftChanges.clear();
                this.rowsWithChanges.clear();
                this.selectedFacilities = [];

                this.allData = this.allData.map(row => ({
                    ...row,
                    isSelected: false
                }));

                // Reload data to get fresh values
                this._dataLoaded = false;
                this.loadData();
            })
            .catch(error => {
                this.errorMessage = this.getErrorMessage(error);
                this.showToast('Error', this.errorMessage, 'error');
                this.isLoading = false;
            });
    }

    buildUpdateData() {
        const modifiedFacilities = [];

        this.draftChanges.forEach((changes, rowId) => {
            const fields = {};
            let hasValidChanges = false;

            const originalRow = this.allData.find(row => row.Id === rowId);
            if (!originalRow) return;

            Object.keys(changes).forEach(fieldName => {
                const originalValue = originalRow.originalValues[fieldName];
                const newValue = changes[fieldName];

                if (newValue !== originalValue) {
                    fields[fieldName] = newValue;
                    hasValidChanges = true;
                }
            });

            if (hasValidChanges && Object.keys(fields).length > 0) {
                modifiedFacilities.push({
                    Id: rowId,
                    fields: fields
                });
            }
        });

        return modifiedFacilities;
    }

    // Computed properties
    get hasData() {
        return this.allData.length > 0;
    }

    get allRowsSelected() {
        return this.filteredData.length > 0 &&
            this.filteredData.every(row => this.selectedFacilities.includes(row.Id));
    }

    get showNoFacilitiesMessage() {
        return !this.isLoading &&
            !this.hasData &&
            this.errorMessage &&
            (this.errorMessage.includes("doesn't have any facilities") ||
                this.errorMessage.includes("There are no facilities"));
    }

    get showActualError() {
        return !this.isLoading &&
            this.errorMessage &&
            !this.errorMessage.includes("doesn't have any facilities") &&
            !this.errorMessage.includes("There are no facilities");
    }

    get facilityCount() {
        return this.buildUpdateData().length;
    }

    get totalFacilityCount() {
        return this.filteredData.length;
    }

    get selectedFacilityCount() {
        return this.selectedFacilities.length;
    }

    get disableUpdateButton() {
        return !this.hasData || this.isLoading || this.facilityCount === 0;
    }

    // Utility methods
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        }));
    }

    getErrorMessage(error) {
        if (error.body && error.body.message) {
            return error.body.message;
        } else if (error.message) {
            return error.message;
        }
        return 'An unknown error occurred';
    }
}