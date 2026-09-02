import { LightningElement, api, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getFacilitiesAndFields from '@salesforce/apex/FacilityEditorController.getFacilitiesAndFields';
import updateFacilities from '@salesforce/apex/FacilityEditorController.updateFacilities';

// Program configuration - maps program checkbox to Launch/On Hold dates
const PROGRAM_CONFIG = [
    { name: 'CCM', checkbox: 'CCM__c', launchDate: 'CCM_Launch_Date__c', onHoldDate: 'CCM_On_Hold_Date__c' },
    { name: 'RPM', checkbox: 'RPM__c', launchDate: 'RPM_Launch_Date__c', onHoldDate: 'RPM_On_Hold_Date__c' },
    { name: 'TCM', checkbox: 'TCM__c', launchDate: 'TCM_Launch_Date__c', onHoldDate: 'TCM_On_Hold_Date__c' },
    { name: 'COCM', checkbox: 'COCM__c', launchDate: 'COCM_Launch_Date__c', onHoldDate: 'COCM_On_Hold_Date__c' },
    { name: 'AHTH', checkbox: 'AHTH__c', launchDate: 'AHTH_Launch_Date__c', onHoldDate: 'AHTH_On_Hold_Date__c' },
    { name: 'APCM', checkbox: 'APCM__c', launchDate: 'APCM_Launch_Date__c', onHoldDate: 'APCM_On_Hold_Date__c' },
    { name: 'BHI', checkbox: 'BHI__c', launchDate: 'BHI_Launch_Date__c', onHoldDate: 'BHI_On_Hold_Date__c' }
];

export default class FacilityEditor extends NavigationMixin(LightningElement) {
    @track allData = [];
    @track filteredData = [];
    @track expandedRows = new Set();
    @track searchTerm = '';
    @track draftChanges = new Map();
    @track rowsWithChanges = new Set();

    // Modal state
    @track showDateModal = false;
    @track modalDates = {};
    @track modalStep = 1; // 1 = facility selection, 2 = program configuration
    @track selectedFacilitiesForModal = new Set();
    @track modalSearchTerm = '';

    fields = [];
    isLoading = true;
    errorMessage = '';

    // Cached update data to avoid recalculating on every getter access
    _cachedUpdateData = null;
    _updateDataDirty = true;

    // Modal escape key handler reference
    _boundEscapeHandler = null;

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

    disconnectedCallback() {
        // Clean up escape key listener if modal is open when component is destroyed
        if (this._boundEscapeHandler) {
            window.removeEventListener('keydown', this._boundEscapeHandler);
            this._boundEscapeHandler = null;
        }
    }

    // =========================================
    // Data Loading
    // =========================================

    loadData() {
        if (!this._recordId) {
            this.errorMessage = 'No Account ID available.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        getFacilitiesAndFields({ accountId: this._recordId })
            .then(result => {
                if (!result || !result.fields || !result.facilities) {
                    throw new Error('Invalid response structure from server');
                }

                this.fields = result.fields;
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

    buildTableData(facilities) {
        const data = [];
        let rowNumber = 1;

        facilities.forEach(facility => {
            const originalValues = {};
            this.fields.forEach(field => {
                originalValues[field.fieldPath] = facility[field.fieldPath];
            });

            const row = {
                Id: facility.Id,
                Name: facility.Name,
                facilityUrl: `/${facility.Id}`,
                originalValues: originalValues,
                rowNumber: rowNumber++,
                ...this.getFieldValues(facility)
            };

            this.computeRowDisplayProperties(row);
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

    computeRowDisplayProperties(row) {
        const isModified = this.rowsWithChanges.has(row.Id);
        const isExpanded = this.expandedRows.has(row.Id);

        row.isExpanded = isExpanded;
        row.expandedKey = row.Id + '-expanded';
        row.rowClass = isModified ? 'row-modified' : '';
        row.expandIcon = isExpanded ? 'utility:chevrondown' : 'utility:chevronright';
        row.expandTooltip = isExpanded ? 'Collapse dates' : 'Expand dates';

        // Program statuses for checkboxes
        row.programStatuses = PROGRAM_CONFIG.map(program => ({
            name: program.name,
            checkbox: program.checkbox,
            isEnabled: row[program.checkbox] || false
        }));

        // Compute if all programs are selected for this row
        row.allProgramsSelected = PROGRAM_CONFIG.every(program => row[program.checkbox]);

        // Enabled programs with date values (for expanded view)
        row.enabledPrograms = PROGRAM_CONFIG
            .filter(program => row[program.checkbox])
            .map(program => {
                const launchDateValue = row[program.launchDate] || '';
                const onHoldDateValue = row[program.onHoldDate] || '';

                return {
                    name: program.name,
                    checkbox: program.checkbox,
                    launchDate: program.launchDate,
                    onHoldDate: program.onHoldDate,
                    launchDateValue: launchDateValue,
                    onHoldDateValue: onHoldDateValue,
                    hasLaunchDateError: false,
                    hasOnHoldDateError: false,
                    hasValidationError: false,
                    launchDateClass: 'date-input',
                    onHoldDateClass: 'date-input'
                };
            });

        row.hasAnyEnabledProgram = row.enabledPrograms.length > 0;
    }

    // =========================================
    // Search & Filter
    // =========================================

    handleSearch(event) {
        this.searchTerm = event.target.value;
        this.filterData();
    }

    filterData() {
        // Mark cache as dirty when data changes
        this._updateDataDirty = true;

        this.filteredData = this.allData
            .filter(row => {
                return !this.searchTerm ||
                    row.Name.toLowerCase().includes(this.searchTerm.toLowerCase());
            })
            .map(row => {
                const displayRow = { ...row };

                // Apply draft changes
                if (this.draftChanges.has(row.Id)) {
                    const changes = this.draftChanges.get(row.Id);
                    Object.keys(changes).forEach(fieldName => {
                        displayRow[fieldName] = changes[fieldName];
                    });
                }

                this.computeRowDisplayProperties(displayRow);
                return displayRow;
            });
    }

    // =========================================
    // Toggle All Programs for a Row
    // =========================================

    handleToggleAllPrograms(event) {
        const rowId = event.target.dataset.id;
        const isChecked = event.target.checked;

        if (!this.draftChanges.has(rowId)) {
            this.draftChanges.set(rowId, {});
        }

        // Toggle all programs ON or OFF
        PROGRAM_CONFIG.forEach(program => {
            this.draftChanges.get(rowId)[program.checkbox] = isChecked;

            // If unchecking, clear dates (set to null)
            if (!isChecked) {
                this.draftChanges.get(rowId)[program.launchDate] = null;
                this.draftChanges.get(rowId)[program.onHoldDate] = null;
            }
        });

        this.rowsWithChanges.add(rowId);

        // Auto-expand row when enabling all programs
        if (isChecked) {
            this.expandedRows.add(rowId);
        }

        // Reconcile state to clean up if no actual changes
        this.reconcileRowState(rowId);

        this.expandedRows = new Set(this.expandedRows);
        this.filterData();
    }

    // =========================================
    // Select All Programs for All Rows (Toolbar)
    // =========================================

    handleSelectAllProgramsForAllRows(event) {
        const isChecked = event.target.checked;

        this.filteredData.forEach(row => {
            if (!this.draftChanges.has(row.Id)) {
                this.draftChanges.set(row.Id, {});
            }

            // Toggle all programs ON or OFF
            PROGRAM_CONFIG.forEach(program => {
                this.draftChanges.get(row.Id)[program.checkbox] = isChecked;

                // If unchecking, clear dates (set to null)
                if (!isChecked) {
                    this.draftChanges.get(row.Id)[program.launchDate] = null;
                    this.draftChanges.get(row.Id)[program.onHoldDate] = null;
                }
            });

            this.rowsWithChanges.add(row.Id);

            // Auto-expand row when enabling all programs
            if (isChecked) {
                this.expandedRows.add(row.Id);
            }

            // Reconcile state to clean up if no actual changes
            this.reconcileRowState(row.Id);
        });

        const action = isChecked ? 'enabled' : 'disabled';
        this.showToast('Success', `All programs ${action} for ${this.filteredData.length} facilities`, 'success');

        this.expandedRows = new Set(this.expandedRows);
        this.filterData();
    }

    // =========================================
    // Expand/Collapse Rows
    // =========================================

    handleToggleExpand(event) {
        const rowId = event.currentTarget.dataset.id;

        if (this.expandedRows.has(rowId)) {
            this.expandedRows.delete(rowId);
        } else {
            this.expandedRows.add(rowId);
        }

        // Trigger reactivity
        this.expandedRows = new Set(this.expandedRows);
        this.filterData();
    }

    // =========================================
    // Program Toggle
    // =========================================

    handleProgramToggle(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const isChecked = event.target.checked;

        if (!this.draftChanges.has(rowId)) {
            this.draftChanges.set(rowId, {});
        }

        this.draftChanges.get(rowId)[fieldName] = isChecked;
        this.rowsWithChanges.add(rowId);

        // If enabling a program, auto-expand the row
        if (isChecked) {
            this.expandedRows.add(rowId);
        } else {
            // If unchecking, clear dates (set to null)
            const program = PROGRAM_CONFIG.find(p => p.checkbox === fieldName);
            if (program) {
                this.draftChanges.get(rowId)[program.launchDate] = null;
                this.draftChanges.get(rowId)[program.onHoldDate] = null;
            }
        }

        // Reconcile state to clean up if no actual changes
        this.reconcileRowState(rowId);

        this.expandedRows = new Set(this.expandedRows);
        this.filterData();
    }

    // =========================================
    // Date Change Handler
    // =========================================

    handleDateChange(event) {
        const rowId = event.target.dataset.id;
        const fieldName = event.target.dataset.field;
        const newValue = event.target.value || null;

        if (!this.draftChanges.has(rowId)) {
            this.draftChanges.set(rowId, {});
        }
        this.draftChanges.get(rowId)[fieldName] = newValue;
        this.rowsWithChanges.add(rowId);

        // Reconcile state to clean up if no actual changes
        this.reconcileRowState(rowId);

        this.filterData();
    }

    // =========================================
    // Date Modal
    // =========================================

    handleOpenDateModal() {
        // Initialize modal - Step 1: Facility Selection
        this.modalStep = 1;
        this.selectedFacilitiesForModal = new Set();
        this.modalSearchTerm = '';
        this.modalDates = {};
        PROGRAM_CONFIG.forEach(program => {
            this.modalDates[program.name] = {
                name: program.name,
                checkbox: program.checkbox,
                launchDate: program.launchDate,
                onHoldDate: program.onHoldDate,
                launchDateValue: '',
                onHoldDateValue: '',
                isIncluded: false // Default to unchecked
            };
        });
        this.showDateModal = true;

        // Add escape key listener for modal
        this._boundEscapeHandler = this.handleEscapeKey.bind(this);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            window.addEventListener('keydown', this._boundEscapeHandler);
        }, 0);
    }

    handleCloseDateModal() {
        this.showDateModal = false;
        this.modalStep = 1;
        this.modalDates = {};
        this.selectedFacilitiesForModal = new Set();
        this.modalSearchTerm = '';

        // Remove escape key listener
        if (this._boundEscapeHandler) {
            window.removeEventListener('keydown', this._boundEscapeHandler);
            this._boundEscapeHandler = null;
        }
    }

    // Modal Step Navigation
    handleModalNext() {
        if (this.selectedFacilitiesForModal.size === 0) {
            this.showToast('Warning', 'Please select at least one facility.', 'warning');
            return;
        }
        this.modalStep = 2;
    }

    handleModalBack() {
        this.modalStep = 1;
    }

    // Modal Facility Selection
    handleModalFacilityToggle(event) {
        const facilityId = event.target.dataset.id;
        const isChecked = event.target.checked;

        const updatedSet = new Set(this.selectedFacilitiesForModal);
        if (isChecked) {
            updatedSet.add(facilityId);
        } else {
            updatedSet.delete(facilityId);
        }
        this.selectedFacilitiesForModal = updatedSet;
    }

    handleModalSelectAllFacilities(event) {
        const isChecked = event.target.checked;
        const updatedSet = new Set(this.selectedFacilitiesForModal);

        // Only toggle facilities that match the current search filter
        this.modalFacilityList.forEach(facility => {
            if (isChecked) {
                updatedSet.add(facility.Id);
            } else {
                updatedSet.delete(facility.Id);
            }
        });

        this.selectedFacilitiesForModal = updatedSet;
    }

    handleModalSearch(event) {
        this.modalSearchTerm = event.target.value;
    }

    handleEscapeKey(event) {
        if (event.key === 'Escape' && this.showDateModal) {
            this.handleCloseDateModal();
        }
    }

    handleModalDateChange(event) {
        const programName = event.target.dataset.program;
        const fieldType = event.target.dataset.fieldtype;
        const value = event.target.value || '';

        if (this.modalDates[programName]) {
            // Create new object reference to trigger reactivity
            const updatedDates = { ...this.modalDates };
            if (fieldType === 'launch') {
                updatedDates[programName] = { ...updatedDates[programName], launchDateValue: value };
            } else if (fieldType === 'onhold') {
                updatedDates[programName] = { ...updatedDates[programName], onHoldDateValue: value };
            }
            this.modalDates = updatedDates;
        }
    }

    handleModalProgramToggle(event) {
        const programName = event.target.dataset.program;
        const isChecked = event.target.checked;

        if (this.modalDates[programName]) {
            // Create new object reference to trigger reactivity
            const updatedDates = { ...this.modalDates };
            updatedDates[programName] = { ...updatedDates[programName], isIncluded: isChecked };
            this.modalDates = updatedDates;
        }
    }

    handleApplyDates() {
        // Check if any programs are selected
        const hasSelectedPrograms = PROGRAM_CONFIG.some(program =>
            this.modalDates[program.name]?.isIncluded
        );

        let appliedCount = 0;
        let programsApplied = [];
        let rowsToExpand = [];

        // Apply only to SELECTED facilities from Step 1
        // OVERRIDE behavior: Clear all programs first, then apply only selected ones
        this.filteredData.forEach(row => {
            if (!this.selectedFacilitiesForModal.has(row.Id)) return;

            if (!this.draftChanges.has(row.Id)) {
                this.draftChanges.set(row.Id, {});
            }

            // First, DISABLE all programs for this facility (override behavior)
            PROGRAM_CONFIG.forEach(program => {
                this.draftChanges.get(row.Id)[program.checkbox] = false;
                // Clear dates when disabling (set to null)
                this.draftChanges.get(row.Id)[program.launchDate] = null;
                this.draftChanges.get(row.Id)[program.onHoldDate] = null;
            });

            // Then, ENABLE only the selected programs from the modal
            PROGRAM_CONFIG.forEach(program => {
                const modalProgram = this.modalDates[program.name];
                if (!modalProgram || !modalProgram.isIncluded) return;

                // Enable the program checkbox
                this.draftChanges.get(row.Id)[program.checkbox] = true;

                // Apply dates from modal
                this.draftChanges.get(row.Id)[program.launchDate] = modalProgram.launchDateValue || null;
                this.draftChanges.get(row.Id)[program.onHoldDate] = modalProgram.onHoldDateValue || null;

                if (!programsApplied.includes(program.name)) {
                    programsApplied.push(program.name);
                }
            });

            this.rowsWithChanges.add(row.Id);
            appliedCount++;

            // Expand row if it has any enabled programs
            if (PROGRAM_CONFIG.some(p => this.draftChanges.get(row.Id)[p.checkbox])) {
                rowsToExpand.push(row.Id);
            }

            // Reconcile state to clean up if no actual changes
            this.reconcileRowState(row.Id);
        });

        // Expand rows that had changes applied
        rowsToExpand.forEach(rowId => this.expandedRows.add(rowId));
        this.expandedRows = new Set(this.expandedRows);

        this.handleCloseDateModal();
        this.filterData();

        if (appliedCount > 0) {
            if (hasSelectedPrograms) {
                this.showToast('Success', `Programs configured for ${appliedCount} facilities: ${programsApplied.join(', ')}`, 'success');
            } else {
                this.showToast('Success', `All programs cleared for ${appliedCount} facilities`, 'success');
            }
        } else {
            this.showToast('Info', 'No changes were applied.', 'info');
        }
    }

    getRowsWithProgramsEnabled() {
        return this.filteredData.filter(row => {
            return PROGRAM_CONFIG.some(program => {
                const draftValue = this.draftChanges.get(row.Id)?.[program.checkbox];
                return draftValue !== undefined ? draftValue : row[program.checkbox];
            });
        });
    }

    get modalProgramList() {
        return PROGRAM_CONFIG.map(program => {
            const modalData = this.modalDates[program.name];
            const isIncluded = modalData?.isIncluded || false;
            const launchDateValue = modalData?.launchDateValue || '';
            const onHoldDateValue = modalData?.onHoldDateValue || '';

            return {
                name: program.name,
                checkbox: program.checkbox,
                launchDate: program.launchDate,
                onHoldDate: program.onHoldDate,
                launchDateValue: launchDateValue,
                onHoldDateValue: onHoldDateValue,
                isIncluded: isIncluded,
                isDisabled: !isIncluded,
                hasLaunchDateError: false,
                hasOnHoldDateError: false,
                launchDateClass: 'modal-date-input',
                onHoldDateClass: 'modal-date-input'
            };
        });
    }

    get modalSubtitle() {
        if (this.modalStep === 1) {
            return `Step 1 of 2: Select facilities to configure`;
        }
        const count = this.selectedFacilitiesForModal.size;
        return `Step 2 of 2: Configure programs for ${count} ${count === 1 ? 'facility' : 'facilities'}`;
    }

    get isModalStep1() {
        return this.modalStep === 1;
    }

    get isModalStep2() {
        return this.modalStep === 2;
    }

    get modalFacilityList() {
        return this.filteredData
            .filter(row => {
                if (!this.modalSearchTerm) return true;
                return row.Name.toLowerCase().includes(this.modalSearchTerm.toLowerCase());
            })
            .map(row => ({
                Id: row.Id,
                Name: row.Name,
                rowNumber: row.rowNumber,
                isSelected: this.selectedFacilitiesForModal.has(row.Id)
            }));
    }

    get allModalFacilitiesSelected() {
        const visibleFacilities = this.modalFacilityList;
        return visibleFacilities.length > 0 &&
            visibleFacilities.every(facility => this.selectedFacilitiesForModal.has(facility.Id));
    }

    get modalFacilityListCount() {
        return this.modalFacilityList.length;
    }

    get selectedFacilityCount() {
        return this.selectedFacilitiesForModal.size;
    }

    get disableModalNext() {
        return this.selectedFacilitiesForModal.size === 0;
    }

    get rowsWithProgramsCount() {
        return this.getRowsWithProgramsEnabled().length;
    }

    get allProgramsSelectedForAllRows() {
        return this.filteredData.length > 0 &&
            this.filteredData.every(row => row.allProgramsSelected);
    }

    // =========================================
    // Save / Cancel
    // =========================================

    handleCancelChanges() {
        this.draftChanges.clear();
        this.rowsWithChanges.clear();
        this.expandedRows.clear();

        // Reset cache
        this._cachedUpdateData = null;
        this._updateDataDirty = true;

        this.filterData();
        this.showToast('Info', 'All pending changes have been discarded.', 'info');
    }

    handleUpdateFacilities() {
        // Validate dates before saving
        const validationErrors = this.validateDates();
        if (validationErrors.length > 0) {
            const errorDetails = validationErrors.slice(0, 5).join('; ');
            const moreCount = validationErrors.length > 5 ? ` and ${validationErrors.length - 5} more errors` : '';
            this.showToast('Validation Error', `${errorDetails}${moreCount}`, 'error');
            return;
        }

        // Use cached data if available, otherwise build fresh
        const facilitiesToUpdate = (this._cachedUpdateData && !this._updateDataDirty)
            ? this._cachedUpdateData
            : this.buildUpdateData();

        if (facilitiesToUpdate.length === 0) {
            this.showToast('Info', 'No changes detected.', 'info');
            return;
        }

        this.isLoading = true;

        updateFacilities({ facilitiesJson: JSON.stringify(facilitiesToUpdate) })
            .then(result => {
                this.showToast('Success', `${result.count} facilities updated successfully!`, 'success');
                this.isLoading = false;

                this.draftChanges.clear();
                this.rowsWithChanges.clear();
                this.expandedRows.clear();

                // Reset cache
                this._cachedUpdateData = null;
                this._updateDataDirty = true;

                this._dataLoaded = false;
                this.loadData();
            })
            .catch(error => {
                this.errorMessage = this.getErrorMessage(error);
                this.showToast('Error', this.errorMessage, 'error');
                this.isLoading = false;
            });
    }

    validateDates() {
        // Launch dates and on hold dates are optional - no validation required
        return [];
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

    // =========================================
    // Computed Properties
    // =========================================

    get hasData() {
        return this.allData.length > 0;
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
        // Use cached value if available to avoid recalculating on every access
        if (this._updateDataDirty || this._cachedUpdateData === null) {
            this._cachedUpdateData = this.buildUpdateData();
            this._updateDataDirty = false;
        }
        return this._cachedUpdateData.length;
    }

    get totalFacilityCount() {
        return this.filteredData.length;
    }

    get disableUpdateButton() {
        return !this.hasData || this.isLoading || this.facilityCount === 0;
    }

    get updateButtonLabel() {
        const count = this.facilityCount;
        return count > 0 ? `Save (${count})` : 'Save';
    }

    get programColumns() {
        return PROGRAM_CONFIG;
    }

    get columnCount() {
        // Expand + # + Name + 7 programs + All Programs
        return 4 + PROGRAM_CONFIG.length;
    }

    // =========================================
    // Utility Methods
    // =========================================

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

    handleNavigateToFacility(event) {
        event.preventDefault();
        const facilityId = event.currentTarget.dataset.id;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: facilityId,
                objectApiName: 'Account',
                actionName: 'view'
            }
        });
    }

    // =========================================
    // State Reconciliation
    // =========================================

    /**
     * Reconciles draft state for a row - removes from tracking if no actual changes exist.
     * This prevents stale highlights and expanded states when values return to original.
     */
    reconcileRowState(rowId) {
        const originalRow = this.allData.find(r => r.Id === rowId);
        if (!originalRow) return;

        const changes = this.draftChanges.get(rowId);
        if (!changes || Object.keys(changes).length === 0) {
            this.draftChanges.delete(rowId);
            this.rowsWithChanges.delete(rowId);
            return;
        }

        // Check if all draft values match originals
        let hasActualChanges = false;
        Object.keys(changes).forEach(fieldName => {
            const originalValue = originalRow.originalValues[fieldName];
            const draftValue = changes[fieldName];

            // Normalize null/undefined comparison
            const normalizedOriginal = originalValue === undefined ? null : originalValue;
            const normalizedDraft = draftValue === undefined ? null : draftValue;

            if (normalizedDraft !== normalizedOriginal) {
                hasActualChanges = true;
            }
        });

        if (!hasActualChanges) {
            this.draftChanges.delete(rowId);
            this.rowsWithChanges.delete(rowId);
        }

        // Collapse row if no programs are enabled
        if (!this.rowHasEnabledPrograms(rowId)) {
            this.expandedRows.delete(rowId);
        }
    }

    /**
     * Checks if a row has any enabled programs (considering drafts).
     */
    rowHasEnabledPrograms(rowId) {
        const originalRow = this.allData.find(r => r.Id === rowId);
        if (!originalRow) return false;

        const changes = this.draftChanges.get(rowId) || {};

        return PROGRAM_CONFIG.some(program => {
            const draftValue = changes[program.checkbox];
            return draftValue !== undefined ? draftValue : originalRow[program.checkbox];
        });
    }
}
