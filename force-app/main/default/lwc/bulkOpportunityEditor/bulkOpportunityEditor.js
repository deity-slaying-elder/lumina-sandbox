import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getOpportunitiesAndFields from '@salesforce/apex/BulkOpportunityEditorController.getOpportunitiesAndFields';
import updateOpportunities from '@salesforce/apex/BulkOpportunityEditorController.updateOpportunities';

export default class BulkOpportunityEditor extends LightningElement {
    @track columns = [];
    @track allData = [];
    @track filteredData = [];
    @track selectedFacilities = [];
    @track selectedOpportunities = [];
    @track selectedTypes = [];
    @track facilitySearchTerm = '';
    @track draftChanges = new Map(); // Map to store staged changes: { recordId: { fieldName: newValue, ... } }
    @track rowsWithChanges = new Set(); // Track which rows have pending changes
    @track showModal = false;

    fields = [];
    facilities = [];
    opportunityTypes = [];
    @track stageNameOptions = [];
    @track typeOptions = [];
    isLoading = true;
    errorMessage = '';
    savedChangesCache = new Map(); // Store changes before confirming

    _recordId;
    _dataLoaded = false;

    // Use getter/setter to trigger data load when recordId is set
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

    // Load opportunities and field set data
    loadData() {
        if (!this._recordId) {
            this.errorMessage = 'No Account ID available. Please ensure this component is used on an Account page.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        getOpportunitiesAndFields({ accountId: this._recordId })
            .then(result => {
                if (!result || !result.fields || !result.facilities) {
                    throw new Error('Invalid response structure from server');
                }

                this.fields = result.fields;
                this.facilities = this.processFacilities(result.facilities);

                // Extract picklist values from field metadata
                this.fields.forEach(field => {
                    if (field.type.toLowerCase() === 'picklist' && field.picklistValues) {
                        if (field.fieldPath === 'StageName') {
                            this.stageNameOptions = field.picklistValues;
                        } else if (field.fieldPath === 'Type') {
                            this.typeOptions = field.picklistValues;
                        }
                    }
                });

                // Extract unique opportunity types
                this.opportunityTypes = this.extractOpportunityTypes(result.facilities);

                this.columns = this.buildColumns(result.fields);
                this.allData = this.buildTableData();
                this.filteredData = [...this.allData];

                // Select all facilities by default
                this.selectedFacilities = this.facilities.map(f => f.Id);

                // Select all types by default
                this.selectedTypes = [...this.opportunityTypes];

                this.isLoading = false;
            })
            .catch(error => {
                console.error('Error loading data:', error);
                let errorMsg = this.getErrorMessage(error);

                // If error is about no opportunities, show friendly message
                if (errorMsg.includes("doesn't have any opportunities") ||
                    errorMsg.includes("No opportunities") ||
                    errorMsg.includes("Script-thrown exception")) {
                    this.errorMessage = "There are no facilities with opportunities linked to this account yet.";
                } else {
                    this.errorMessage = errorMsg;
                }

                this.isLoading = false;
            });
    }

    // Build columns for custom table including Facility column
    buildColumns(fields) {
        const columns = [
            {
                label: 'Opportunity Name',
                fieldName: 'Name',
                displayField: 'Name',
                type: 'text',
                editable: false,
                isLink: true,
                linkField: 'opportunityUrl',
                inputType: 'text',
                isPicklist: false
            },
            {
                label: 'Facility',
                fieldName: 'facilityName',
                displayField: 'facilityName',
                type: 'text',
                editable: false,
                inputType: 'text',
                isPicklist: false
            }
        ];

        fields.forEach(field => {
            const type = field.type.toLowerCase();
            let inputType = 'text';
            let isPicklist = false;

            // Map field types to lightning-input types
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
                inputType = 'text'; // Not used for picklists, but set as fallback
            }

            const column = {
                label: field.label,
                fieldName: field.fieldPath,
                displayField: field.fieldPath,
                type: type,
                // Make non-updateable fields (formula fields, system fields) read-only
                editable: field.updateable || type === 'picklist',
                inputType: inputType,
                isPicklist: isPicklist,
                optionsField: isPicklist ? field.fieldPath + 'Options' : null
            };

            // Store picklist values for rendering
            if (type === 'picklist' && field.picklistValues) {
                column.picklistValues = field.picklistValues;
            }

            columns.push(column);
        });

        return columns;
    }

    // Process facilities
    processFacilities(facilities) {
        if (!facilities || !Array.isArray(facilities)) {
            console.error('Facilities is not an array:', facilities);
            return [];
        }

        return facilities.map(facility => {
            const opportunities = facility.opportunities || [];

            const processedOpportunities = opportunities.map(opp => {
                // Store original values for change detection
                const originalValues = {};
                this.fields.forEach(field => {
                    originalValues[field.fieldPath] = opp[field.fieldPath];
                });

                return {
                    ...opp,
                    originalValues: originalValues,
                    facilityId: facility.Id,
                    facilityName: facility.Name
                };
            });

            return {
                Id: facility.Id,
                Name: facility.Name,
                opportunityCount: facility.opportunityCount || 0,
                opportunities: processedOpportunities,
                selected: true // Default to selected
            };
        });
    }

    // Extract unique opportunity types
    extractOpportunityTypes(facilities) {
        const typesSet = new Set();

        facilities.forEach(facility => {
            facility.opportunities.forEach(opp => {
                if (opp.Type) {
                    typesSet.add(opp.Type);
                }
            });
        });

        return Array.from(typesSet).sort();
    }

    // Build flat table data from facilities with cell values pre-computed
    buildTableData() {
        const data = [];
        let rowNumber = 1;

        this.facilities.forEach(facility => {
            facility.opportunities.forEach(opp => {
                const row = {
                    Id: opp.Id,
                    Name: opp.Name,
                    opportunityUrl: `/${opp.Id}`, // Salesforce record URL
                    Type: opp.Type,
                    facilityId: facility.Id,
                    facilityName: facility.Name,
                    originalValues: opp.originalValues,
                    rowNumber: rowNumber++,
                    isSelected: this.selectedOpportunities.includes(opp.Id),
                    ...this.getFieldValues(opp)
                };

                // Add picklist options to each row for combobox rendering
                // The field name must match: fieldPath + 'Options'
                row.StageNameOptions = this.stageNameOptions;
                row.TypeOptions = this.typeOptions;

                // Pre-compute cell values for each column to avoid dynamic property access in template
                // This must happen AFTER adding the options fields
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
        });

        return data;
    }

    // Extract field values from opportunity
    getFieldValues(opp) {
        const values = {};
        this.fields.forEach(field => {
            values[field.fieldPath] = opp[field.fieldPath];
        });
        return values;
    }

    // Handle facility search
    handleFacilitySearch(event) {
        this.facilitySearchTerm = event.target.value;
        this.filterData();
    }

    // Handle select all facilities
    handleSelectAllFacilities(event) {
        const isChecked = event.target.checked;

        // Get the IDs of filtered facilities
        const filteredIds = this.filteredFacilities.map(f => f.Id);

        // Update all facilities' selected property
        this.facilities = this.facilities.map(facility => {
            if (filteredIds.includes(facility.Id)) {
                return { ...facility, selected: isChecked };
            }
            return facility;
        });

        if (isChecked) {
            // Select all filtered facilities
            this.selectedFacilities = this.filteredFacilities.map(f => f.Id);
        } else {
            // Deselect all filtered facilities
            this.selectedFacilities = this.selectedFacilities.filter(
                id => !filteredIds.includes(id)
            );
        }

        this.filterData();
    }

    // Handle individual facility selection
    handleFacilitySelection(event) {
        const facilityId = event.target.dataset.facilityId;
        const isChecked = event.target.checked;

        // Update the facility's selected property
        this.facilities = this.facilities.map(facility => {
            if (facility.Id === facilityId) {
                return { ...facility, selected: isChecked };
            }
            return facility;
        });

        if (isChecked) {
            this.selectedFacilities = [...this.selectedFacilities, facilityId];
        } else {
            this.selectedFacilities = this.selectedFacilities.filter(id => id !== facilityId);
        }

        this.filterData();
    }

    // Filter data based on selected facilities, types, and search term
    filterData() {
        this.filteredData = this.allData
            .filter(row => {
                // Filter by selected facilities
                const facilityMatch = this.selectedFacilities.includes(row.facilityId);

                // Filter by selected types (if type is null/undefined, include it if no types are selected or all types are selected)
                const typeMatch = this.selectedTypes.length === 0 ||
                                 this.selectedTypes.length === this.opportunityTypes.length ||
                                 this.selectedTypes.includes(row.Type) ||
                                 (!row.Type && this.selectedTypes.includes('None'));

                // Filter by search term (if any)
                const searchMatch = !this.facilitySearchTerm ||
                                   row.facilityName.toLowerCase().includes(this.facilitySearchTerm.toLowerCase());

                return facilityMatch && typeMatch && searchMatch;
            })
            .map(row => {
                // MERGE DRAFT CHANGES with original row data
                const displayRow = { ...row };

                // Apply any pending draft changes to this row
                if (this.draftChanges.has(row.Id)) {
                    const changes = this.draftChanges.get(row.Id);
                    Object.keys(changes).forEach(fieldName => {
                        displayRow[fieldName] = changes[fieldName];
                    });
                }

                // Rebuild cells array to reflect current values (including drafts)
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

    // Handle field change in custom table
    handleFieldChange(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        // Handle checkbox values differently - they use checked property, not detail.value
        const isCheckbox = event.target.type === 'checkbox';
        const newValue = isCheckbox ? event.target.checked : event.detail.value;

        // If there are selected opportunities, apply changes to all selected
        if (this.selectedOpportunities.length > 1 && this.selectedOpportunities.includes(rowId)) {
            // Apply to all selected rows - STORE IN DRAFT
            this.selectedOpportunities.forEach(selectedRowId => {
                if (!this.draftChanges.has(selectedRowId)) {
                    this.draftChanges.set(selectedRowId, {});
                }
                this.draftChanges.get(selectedRowId)[fieldName] = newValue;
                this.rowsWithChanges.add(selectedRowId);
            });
            this.showToast('Success', `${fieldName} updated for ${this.selectedOpportunities.length} selected opportunities. Click "Update Opportunities" to save.`, 'success');
        } else {
            // Update only the edited row - STORE IN DRAFT
            if (!this.draftChanges.has(rowId)) {
                this.draftChanges.set(rowId, {});
            }
            this.draftChanges.get(rowId)[fieldName] = newValue;
            this.rowsWithChanges.add(rowId);
        }

        // Rebuild filtered data to show pending changes
        this.filterData();
    }

    // Handle row selection checkbox
    handleRowSelect(event) {
        const rowId = event.target.dataset.id;
        const isChecked = event.target.checked;

        if (isChecked) {
            if (!this.selectedOpportunities.includes(rowId)) {
                this.selectedOpportunities = [...this.selectedOpportunities, rowId];
            }
        } else {
            this.selectedOpportunities = this.selectedOpportunities.filter(id => id !== rowId);
        }

        // Update row selection state
        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: this.selectedOpportunities.includes(row.Id)
        }));

        this.filterData();
    }

    // Handle select all rows checkbox
    handleSelectAllRows(event) {
        const isChecked = event.target.checked;

        if (isChecked) {
            // Select all visible rows
            this.selectedOpportunities = this.filteredData.map(row => row.Id);
        } else {
            // Deselect all
            this.selectedOpportunities = [];
        }

        // Update row selection state
        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: this.selectedOpportunities.includes(row.Id)
        }));

        this.filterData();
    }

    // Handle type selection
    handleTypeSelection(event) {
        const type = event.target.dataset.type;
        const isChecked = event.target.checked;

        if (isChecked) {
            this.selectedTypes = [...this.selectedTypes, type];
        } else {
            this.selectedTypes = this.selectedTypes.filter(t => t !== type);
        }

        this.filterData();
    }

    // Handle select all types
    handleSelectAllTypes(event) {
        const isChecked = event.target.checked;

        if (isChecked) {
            this.selectedTypes = [...this.opportunityTypes];
        } else {
            this.selectedTypes = [];
        }

        this.filterData();
    }

    // Handle StageName change for selected opportunities
    handleStageNameChange(event) {
        const newStage = event.detail.value;
        const combobox = event.target;

        if (this.selectedOpportunities.length === 0) {
            this.showToast('Info', 'Please select opportunities from the table first', 'info');
            // Reset the combobox
            combobox.value = '';
            return;
        }

        // Store changes in draft - NOT directly in allData
        this.selectedOpportunities.forEach(rowId => {
            if (!this.draftChanges.has(rowId)) {
                this.draftChanges.set(rowId, {});
            }
            this.draftChanges.get(rowId)['StageName'] = newStage;
            this.rowsWithChanges.add(rowId);
        });

        this.filterData();
        this.showToast('Success', `Stage updated for ${this.selectedOpportunities.length} selected opportunities. Click "Update Opportunities" to save.`, 'success');

        // Clear the combobox after applying
        combobox.value = '';
    }

    // Handle Type change for selected opportunities
    handleTypeChange(event) {
        const newType = event.detail.value;
        const combobox = event.target;

        if (this.selectedOpportunities.length === 0) {
            this.showToast('Info', 'Please select opportunities from the table first', 'info');
            // Reset the combobox
            combobox.value = '';
            return;
        }

        // Store changes in draft - NOT directly in allData
        this.selectedOpportunities.forEach(rowId => {
            if (!this.draftChanges.has(rowId)) {
                this.draftChanges.set(rowId, {});
            }
            this.draftChanges.get(rowId)['Type'] = newType;
            this.rowsWithChanges.add(rowId);
        });

        this.filterData();
        this.showToast('Success', `Type updated for ${this.selectedOpportunities.length} selected opportunities. Click "Update Opportunities" to save.`, 'success');

        // Clear the combobox after applying
        combobox.value = '';
    }

    // Handle cancel changes - clear all draft changes
    handleCancelChanges() {
        // Clear all draft changes
        this.draftChanges.clear();
        this.rowsWithChanges.clear();

        // Clear selections and update isSelected property
        this.selectedOpportunities = [];
        this.allData = this.allData.map(row => ({
            ...row,
            isSelected: false
        }));

        this.filterData();

        this.showToast('Info', 'All pending changes have been discarded.', 'info');
    }

    // Handle opening the bulkOpportunityCreatorModal
    handleNewOpportunities() {
        this.showModal = true;
    }

    // Handle closing the modal
    handleCloseModal() {
        this.showModal = false;
        // Reload data to show newly created opportunities
        this._dataLoaded = false;
        this.loadData();
    }

    // Handle update opportunities
    handleUpdateOpportunities() {
        const opportunitiesToUpdate = this.buildUpdateData();

        if (opportunitiesToUpdate.length === 0) {
            this.showToast('Info', 'No changes detected. Please modify at least one field to update.', 'info');
            return;
        }

        this.isLoading = true;

        updateOpportunities({ opportunitiesJson: JSON.stringify(opportunitiesToUpdate) })
            .then(result => {
                this.showToast('Success', `${result.count} opportunities updated successfully!`, 'success');
                this.isLoading = false;

                // Clear draft changes after successful save
                this.draftChanges.clear();
                this.rowsWithChanges.clear();

                // Clear selections and update isSelected property
                this.selectedOpportunities = [];
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

    // Build update data - read from draft changes
    buildUpdateData() {
        const modifiedOpportunities = [];

        // ONLY include rows that have draft changes
        this.draftChanges.forEach((changes, rowId) => {
            const fields = {};
            let hasValidChanges = false;

            // Find the original row to compare with
            const originalRow = this.allData.find(row => row.Id === rowId);
            if (!originalRow) return;

            // Only include fields that actually changed (compare with original)
            Object.keys(changes).forEach(fieldName => {
                const originalValue = originalRow.originalValues[fieldName];
                const newValue = changes[fieldName];

                // Only include if the new value differs from the original
                if (newValue !== originalValue) {
                    fields[fieldName] = newValue;
                    hasValidChanges = true;
                }
            });

            if (hasValidChanges && Object.keys(fields).length > 0) {
                modifiedOpportunities.push({
                    Id: rowId,
                    fields: fields
                });
            }
        });

        return modifiedOpportunities;
    }

    // Computed properties
    get hasData() {
        return this.allData.length > 0;
    }

    get allRowsSelected() {
        return this.filteredData.length > 0 &&
               this.filteredData.every(row => this.selectedOpportunities.includes(row.Id));
    }

    get showNoOpportunitiesMessage() {
        return !this.isLoading &&
               !this.hasData &&
               this.errorMessage &&
               (this.errorMessage.includes("doesn't have any opportunities to edit") ||
                this.errorMessage.includes("There are no facilities with opportunities"));
    }

    get showActualError() {
        return !this.isLoading &&
               this.errorMessage &&
               !this.errorMessage.includes("doesn't have any opportunities to edit") &&
               !this.errorMessage.includes("There are no facilities with opportunities");
    }

    get opportunityCount() {
        return this.buildUpdateData().length;
    }

    get totalOpportunityCount() {
        return this.filteredData.length;
    }

    get disableUpdateButton() {
        return !this.hasData || this.isLoading || this.opportunityCount === 0;
    }

    get filteredFacilities() {
        if (!this.facilitySearchTerm) {
            return this.facilities;
        }
        return this.facilities.filter(facility =>
            facility.Name.toLowerCase().includes(this.facilitySearchTerm.toLowerCase())
        );
    }

    get allFacilitiesSelected() {
        if (this.filteredFacilities.length === 0) {
            return false;
        }
        return this.filteredFacilities.every(facility =>
            this.selectedFacilities.includes(facility.Id)
        );
    }

    get selectedOpportunityCount() {
        return this.selectedOpportunities.length;
    }

    get allTypesSelected() {
        return this.opportunityTypes.length > 0 &&
               this.selectedTypes.length === this.opportunityTypes.length;
    }

    get hasOpportunityTypes() {
        return this.opportunityTypes.length > 0;
    }

    // Check if a facility is selected
    isFacilitySelected(facilityId) {
        return this.selectedFacilities.includes(facilityId);
    }

    // Check if a type is selected
    isTypeSelected(type) {
        return this.selectedTypes.includes(type);
    }

    // Get opportunity types with selection state
    get opportunityTypesWithSelection() {
        return this.opportunityTypes.map(type => ({
            value: type,
            label: type,
            selected: this.selectedTypes.includes(type)
        }));
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