import { LightningElement, api, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getInitialData from '@salesforce/apex/BulkOpportunityCreatorController.getInitialData';
import createOpportunities from '@salesforce/apex/BulkOpportunityCreatorController.createOpportunities';

export default class BulkOpportunityCreatorModal extends LightningElement {
    @track facilities = [];
    @track typeOptions = [];
    @track fieldSetFields = [];
    @track isLoading = true;
    @track errorMessage = '';
    @track facilitySearchTerm = '';

    _recordId;
    _dataLoaded = false;

    // Use getter/setter to trigger data load when recordId is set
    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        // Load data when recordId is set and we haven't loaded yet
        if (value && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadInitialData();
        }
    }

    connectedCallback() {
        // Only load if recordId is already set (shouldn't normally happen)
        if (this._recordId && !this._dataLoaded) {
            this._dataLoaded = true;
            this.loadInitialData();
        }
        // Disabled MutationObserver as it causes flickering
        // this.setupDatePickerObserver();
    }

    renderedCallback() {
        // Fix z-index for date pickers to appear above other elements
        this.fixDatePickerZIndex();
    }

    setupDatePickerObserver() {
        // Maximum z-index value
        const MAX_Z_INDEX = '2147483647';

        // Track processed elements to avoid re-processing
        const processedElements = new WeakSet();

        // Watch for any datepicker/dropdown being added to the DOM
        const observer = new MutationObserver((mutations) => {
            mutations.forEach((mutation) => {
                mutation.addedNodes.forEach((node) => {
                    if (node.nodeType === 1) { // Element node
                        // Skip if already processed
                        if (processedElements.has(node)) return;

                        // Check if the node itself is a datepicker or dropdown
                        if (node.classList) {
                            const isDatepicker = node.classList.contains('slds-datepicker') ||
                                                node.classList.contains('slds-dropdown') ||
                                                node.classList.contains('slds-dropdown__list') ||
                                                node.className.includes('datepicker');

                            if (isDatepicker) {
                                node.style.setProperty('z-index', MAX_Z_INDEX, 'important');
                                node.style.setProperty('position', 'fixed', 'important');
                                node.style.setProperty('pointer-events', 'auto', 'important');
                                processedElements.add(node);
                            }
                        }

                        // Check children
                        if (node.querySelectorAll) {
                            const datepickers = node.querySelectorAll('.slds-datepicker, .slds-dropdown, .slds-dropdown__list, [class*="datepicker"]');
                            datepickers.forEach(picker => {
                                if (!processedElements.has(picker)) {
                                    picker.style.setProperty('z-index', MAX_Z_INDEX, 'important');
                                    picker.style.setProperty('position', 'fixed', 'important');
                                    picker.style.setProperty('pointer-events', 'auto', 'important');
                                    processedElements.add(picker);
                                }
                            });
                        }
                    }
                });
            });
        });

        // Start observing the entire document
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        // Store observer to disconnect later if needed
        this._datePickerObserver = observer;
    }

    disconnectedCallback() {
        // Clean up observer
        if (this._datePickerObserver) {
            this._datePickerObserver.disconnect();
        }
    }

    fixDatePickerZIndex() {
        const MAX_Z_INDEX = '2147483647';
        const dateInputs = this.template.querySelectorAll('lightning-input[type="date"]');

        dateInputs.forEach((input) => {
            // Skip if already processed
            if (input.dataset.zindexFixed) return;
            input.dataset.zindexFixed = 'true';

            // Force the lightning-input itself to have high z-index
            input.style.setProperty('z-index', '10000', 'important');
            input.style.position = 'relative';

            // Add focus event to bump z-index when calendar opens
            input.addEventListener('focus', () => {
                // Set lightning-input z-index to maximum
                input.style.setProperty('z-index', MAX_Z_INDEX, 'important');

                // That's it - let CSS handle everything else like the type cards do
            });

            // Reset z-index on blur
            input.addEventListener('blur', () => {
                setTimeout(() => {
                    input.style.setProperty('z-index', '10000', 'important');

                    const parent = input.closest('.type-option-card, .type-config-row, .facility-card, .facility-details');
                    if (parent) {
                        parent.style.zIndex = '';
                    }

                    // Restore z-index of all other cards
                    const allCards = this.template.querySelectorAll('.facility-card, .type-option-card');
                    allCards.forEach(card => {
                        card.style.zIndex = '';
                    });

                    // Restore z-index of all checkboxes
                    const allCheckboxes = this.template.querySelectorAll('lightning-input[type="checkbox"]');
                    allCheckboxes.forEach(checkbox => {
                        checkbox.style.zIndex = '';
                    });
                }, 500);
            });
        });
    }

    loadInitialData() {
        // Safety check - ensure we have a recordId
        if (!this._recordId) {
            this.errorMessage = 'No Account ID available. Please ensure this component is used on an Account page.';
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        getInitialData({ accountId: this._recordId })
            .then(result => {
                // Initialize fieldSet fields with default values
                this.fieldSetFields = result.fieldSetFields.map(field => ({
                    ...field,
                    defaultValue: this.getDefaultValueForField(field)
                }));

                // Initialize facilities with selection tracking
                this.facilities = result.facilities.map(facility => ({
                    ...facility,
                    selected: false,
                    expanded: false,
                    expandIconName: 'utility:chevronright',
                    types: []
                }));

                // Initialize type options with selection tracking and field values
                this.typeOptions = result.typeOptions.map(type => ({
                    ...type,
                    selected: false,
                    fieldValues: this.initializeFieldValues(),
                    fields: this.initializeTypeFields()
                }));

                this.isLoading = false;
            })
            .catch(error => {
                this.errorMessage = this.getErrorMessage(error);
                this.isLoading = false;
            });
    }

    getDefaultValueForField(field) {
        if (field.type === 'DATE') {
            const today = new Date();
            today.setDate(today.getDate() + 30); // Default to 30 days from now
            return today.toISOString().split('T')[0];
        }
        // Default StageName to 'Proposal'
        if (field.apiName === 'StageName') {
            return 'Proposal';
        }
        return null;
    }

    initializeFieldValues() {
        const values = {};
        if (this.fieldSetFields && this.fieldSetFields.length > 0) {
            this.fieldSetFields.forEach(field => {
                values[field.apiName] = field.defaultValue;
            });
        }
        return values;
    }

    initializeTypeFields() {
        // Create array of fields with embedded values for template iteration
        if (!this.fieldSetFields || this.fieldSetFields.length === 0) {
            return [];
        }
        return this.fieldSetFields.map(field => ({
            ...field,
            value: field.defaultValue,
            defaultLabel: `Default ${field.label}`
        }));
    }

    getDefaultDate() {
        const today = new Date();
        today.setDate(today.getDate() + 30); // Default to 30 days from now
        return today.toISOString().split('T')[0];
    }

    getErrorMessage(error) {
        let message = '';

        if (error.body && error.body.message) {
            message = error.body.message;
        } else if (error.message) {
            message = error.message;
        } else {
            return 'Unknown error occurred';
        }

        // Clean up the error message by removing prefixes like "Error retrieving initial data: "
        // This extracts the actual user-friendly message
        if (message.includes('No facilities found')) {
            return 'No facilities found for this account.';
        }

        // Extract message from trigger/validation errors
        // Pattern: "Insert failed. First exception on row 0; first error: ERROR_TYPE, Actual Message: []"
        const validationMatch = message.match(/first error:\s*[A-Z_]+,\s*(.+?):\s*\[/);
        if (validationMatch && validationMatch[1]) {
            return validationMatch[1].trim();
        }

        // Remove common error prefixes for other error types
        message = message.replace(/^Insert failed\.\s*/i, '');
        message = message.replace(/^Update failed\.\s*/i, '');
        message = message.replace(/^First exception on row \d+;\s*/i, '');
        message = message.replace(/^first error:\s*[A-Z_]+,\s*/i, '');
        message = message.replace(/:\s*\[\]$/i, '');
        message = message.replace(/^Error retrieving initial data:\s*/i, '');
        message = message.replace(/^Error creating opportunities:\s*/i, '');
        message = message.replace(/^Script-thrown exception\s*/i, '');

        return message.trim();
    }

    // Handle type selection at the global level
    handleTypeSelection(event) {
        const typeValue = event.target.dataset.type;
        const isChecked = event.target.checked;

        this.typeOptions = this.typeOptions.map(type => {
            if (type.value === typeValue) {
                return { ...type, selected: isChecked };
            }
            return type;
        });

        // Update all selected facilities with this type
        this.updateFacilityTypes();
    }

    // Handle default field value change for a type
    handleDefaultFieldChange(event) {
        const typeValue = event.target.dataset.type;
        const fieldName = event.target.dataset.field;
        const newValue = event.target.value;

        this.typeOptions = this.typeOptions.map(type => {
            if (type.value === typeValue) {
                const updatedFieldValues = { ...type.fieldValues };
                updatedFieldValues[fieldName] = newValue;

                // Update the fields array to reflect the new value
                const updatedFields = type.fields.map(field => {
                    if (field.apiName === fieldName) {
                        return { ...field, value: newValue };
                    }
                    return field;
                });

                return { ...type, fieldValues: updatedFieldValues, fields: updatedFields };
            }
            return type;
        });

        // Update all facilities with these new default values
        this.updateFacilityTypes();
    }

    // Handle facility selection
    handleFacilitySelection(event) {
        const facilityId = event.target.dataset.facilityId;
        const isChecked = event.target.checked;

        this.facilities = this.facilities.map(facility => {
            if (facility.Id === facilityId) {
                const updatedFacility = {
                    ...facility,
                    selected: isChecked,
                    expanded: false,
                    expandIconName: 'utility:chevronright'
                };
                if (isChecked) {
                    // When facility is selected, initialize with selected types
                    updatedFacility.types = this.getSelectedTypes();
                } else {
                    // When facility is deselected, clear types
                    updatedFacility.types = [];
                }
                return updatedFacility;
            }
            return facility;
        });
    }

    // Handle toggling facility details expansion
    handleToggleFacilityDetails(event) {
        const facilityId = event.currentTarget.dataset.facilityId;

        this.facilities = this.facilities.map(facility => {
            if (facility.Id === facilityId) {
                const newExpanded = !facility.expanded;
                return {
                    ...facility,
                    expanded: newExpanded,
                    expandIconName: newExpanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return facility;
        });
    }

    // Handle type selection for a specific facility
    handleFacilityTypeSelection(event) {
        const facilityId = event.target.dataset.facilityId;
        const typeValue = event.target.dataset.type;
        const isChecked = event.target.checked;

        this.facilities = this.facilities.map(facility => {
            if (facility.Id === facilityId) {
                const updatedTypes = facility.types.map(type => {
                    if (type.value === typeValue) {
                        return { ...type, selected: isChecked };
                    }
                    return type;
                });
                return { ...facility, types: updatedTypes };
            }
            return facility;
        });
    }

    // Handle field value change for a specific facility and type
    handleFacilityFieldChange(event) {
        const facilityId = event.target.dataset.facilityId;
        const typeValue = event.target.dataset.type;
        const fieldName = event.target.dataset.field;
        const newValue = event.target.value;

        this.facilities = this.facilities.map(facility => {
            if (facility.Id === facilityId) {
                const updatedTypes = facility.types.map(type => {
                    if (type.value === typeValue) {
                        const updatedFieldValues = { ...type.fieldValues };
                        updatedFieldValues[fieldName] = newValue;

                        // Update the fields array to reflect the new value
                        const updatedFields = type.fields.map(field => {
                            if (field.apiName === fieldName) {
                                return { ...field, value: newValue };
                            }
                            return field;
                        });

                        return { ...type, fieldValues: updatedFieldValues, fields: updatedFields };
                    }
                    return type;
                });
                return { ...facility, types: updatedTypes };
            }
            return facility;
        });
    }

    // Get selected types with their default field values
    getSelectedTypes() {
        return this.typeOptions
            .filter(type => type.selected)
            .map(type => ({
                label: type.label,
                value: type.value,
                selected: true,
                fieldValues: { ...type.fieldValues },
                fields: type.fields.map(f => ({ ...f }))
            }));
    }

    // Update facility types when global type selection changes
    updateFacilityTypes() {
        const selectedTypes = this.getSelectedTypes();

        this.facilities = this.facilities.map(facility => {
            if (facility.selected) {
                // Preserve existing facility-specific overrides
                const updatedTypes = selectedTypes.map(selectedType => {
                    const existingType = facility.types.find(t => t.value === selectedType.value);
                    if (existingType) {
                        // Keep the existing close date and selection status
                        return existingType;
                    }
                    // New type, use default
                    return selectedType;
                });
                return {
                    ...facility,
                    types: updatedTypes,
                    expandIconName: facility.expanded ? 'utility:chevrondown' : 'utility:chevronright'
                };
            }
            return facility;
        });
    }

    // Handle create opportunities button click
    handleCreateOpportunities() {
        const opportunitiesToCreate = this.buildOpportunitiesData();

        if (opportunitiesToCreate.length === 0) {
            this.showToast('Warning', 'Please select at least one facility and opportunity type', 'warning');
            return;
        }

        // Validate that all required fields have values
        const requiredFields = this.fieldSetFields.filter(f => f.required);
        const hasInvalidFields = opportunitiesToCreate.some(opp => {
            return requiredFields.some(field => {
                const value = opp.fieldValues[field.apiName];
                return !value || value === '';
            });
        });

        if (hasInvalidFields) {
            this.showToast('Error', 'Please provide values for all required fields', 'error');
            return;
        }

        this.isLoading = true;

        createOpportunities({
            accountId: this._recordId,
            opportunitiesJson: JSON.stringify(opportunitiesToCreate)
        })
            .then(result => {
                this.showToast('Success', `${result.count} opportunities created successfully!`, 'success');
                this.isLoading = false;
                // Dispatch event to refresh related lists
                this.dispatchEvent(new CustomEvent('opportunitiescreated', {
                    detail: { count: result.count }
                }));
                // Close the modal after successful creation
                this.handleClose();
            })
            .catch(error => {
                this.errorMessage = this.getErrorMessage(error);
                this.isLoading = false;
            });
    }

    // Build the data structure for opportunities to create
    buildOpportunitiesData() {
        const opportunities = [];

        this.facilities.forEach(facility => {
            if (facility.selected && facility.types) {
                facility.types.forEach(type => {
                    if (type.selected) {
                        opportunities.push({
                            name: `${facility.Name} - ${type.label}`,
                            facilityId: facility.Id,
                            facilityName: facility.Name,
                            type: type.value,
                            fieldValues: type.fieldValues || {}
                        });
                    }
                });
            }
        });

        return opportunities;
    }

    // Reset the form to initial state
    resetForm() {
        this.loadInitialData();
    }

    // Handle cancel button click
    handleCancel() {
        this.resetForm();
    }

    // Handle close button click (for modal)
    handleClose() {
        // Dispatch custom event for when used as a child component
        this.dispatchEvent(new CustomEvent('close'));

        // Also dispatch CloseActionScreenEvent for when used as Screen Action
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // Handle go back button (clear error and return to form)
    handleGoBack() {
        this.errorMessage = '';
    }

    // Show toast notification
    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Get Lightning input type based on field type
    getLightningInputType(fieldType) {
        const typeMap = {
            'BOOLEAN': 'checkbox',
            'CURRENCY': 'number',
            'DATE': 'date',
            'DATETIME': 'datetime',
            'DOUBLE': 'number',
            'EMAIL': 'email',
            'INTEGER': 'number',
            'PERCENT': 'number',
            'PHONE': 'tel',
            'PICKLIST': 'text', // Will be handled separately with combobox
            'STRING': 'text',
            'TEXTAREA': 'text',
            'URL': 'url'
        };
        return typeMap[fieldType] || 'text';
    }

    // Handle select all facilities
    handleSelectAllFacilities(event) {
        const isChecked = event.target.checked;

        // Update all filtered facilities to match the select all state
        this.facilities = this.facilities.map(facility => {
            // Only update facilities that match the search filter
            if (this.isFacilityVisible(facility)) {
                const updatedFacility = {
                    ...facility,
                    selected: isChecked,
                    expanded: false,
                    expandIconName: 'utility:chevronright'
                };
                if (isChecked) {
                    updatedFacility.types = this.getSelectedTypes();
                } else {
                    updatedFacility.types = [];
                }
                return updatedFacility;
            }
            return facility;
        });
    }

    // Handle facility search
    handleFacilitySearch(event) {
        this.facilitySearchTerm = event.target.value;
    }

    // Helper to check if facility matches search
    isFacilityVisible(facility) {
        if (!this.facilitySearchTerm) {
            return true;
        }
        return facility.Name.toLowerCase().includes(this.facilitySearchTerm.toLowerCase());
    }

    // Computed properties
    get hasData() {
        return this.facilities.length > 0 || this.typeOptions.length > 0;
    }

    get hasFacilities() {
        return this.facilities.length > 0;
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
        const visibleFacilities = this.filteredFacilities;
        if (visibleFacilities.length === 0) {
            return false;
        }
        return visibleFacilities.every(facility => facility.selected);
    }

    get hasSelections() {
        return this.totalOpportunitiesCount > 0;
    }

    get totalOpportunitiesCount() {
        return this.buildOpportunitiesData().length;
    }

    get disableCreateButton() {
        return this.totalOpportunitiesCount === 0 || this.isLoading;
    }
}