import { LightningElement, track } from 'lwc';
import listRetries from '@salesforce/apex/AIRetryAdminController.listRetries';
import retryNow from '@salesforce/apex/AIRetryAdminController.retryNow';

const COLUMNS = [
    { label: 'Operation', fieldName: 'operation' },
    { label: 'Status', fieldName: 'status' },
    { label: 'Attempts', fieldName: 'attempts', type: 'number' },
    { label: 'Contact', fieldName: 'contactUrl', type: 'url', typeAttributes: { label: { fieldName: 'contactId' }, target: '_blank' } },
    { label: 'Campaign Member', fieldName: 'campaignMemberUrl', type: 'url', typeAttributes: { label: { fieldName: 'campaignMemberId' }, target: '_blank' } },
    { label: 'Next Run', fieldName: 'nextRunAt', type: 'date' },
    { label: 'Last Error', fieldName: 'lastError', wrapText: true }
];

export default class AiRetryAdmin extends LightningElement {
    columns = COLUMNS;
    @track rows = [];
    selectedRows = [];

    connectedCallback() {
        this.loadRows();
    }

    get noSelection() {
        return this.selectedRows.length === 0;
    }

    async loadRows() {
        this.rows = await listRetries();
    }

    handleSelection(event) {
        this.selectedRows = event.detail.selectedRows.map((row) => row.id);
    }

    async retrySelected() {
        await retryNow({ retryIds: this.selectedRows });
        this.selectedRows = [];
        await this.loadRows();
    }

    async retryAll() {
        await retryNow({ retryIds: [] });
        this.selectedRows = [];
        await this.loadRows();
    }
}