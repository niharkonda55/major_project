/*
 * Land Token Contract - Blockchain Land Registry
 * ABAC enforced: VRO creates records, MRO transfers
 * Immutable - no delete operations
 */

'use strict';

const { Contract } = require('fabric-contract-api');
const stringify = require('json-stringify-deterministic');
const sortKeys = require('sort-keys-recursive');

class LandTokenContract extends Contract {

    async _assertVRO(ctx) {
        const role = ctx.clientIdentity.getAttributeValue('role');
        if (role !== 'VRO') {
            throw new Error(`Access denied: role=VRO required, got role=${role || 'none'}`);
        }
    }

    async _assertMRO(ctx) {
        const role = ctx.clientIdentity.getAttributeValue('role');
        if (role !== 'MRO') {
            throw new Error(`Access denied: role=MRO required, got role=${role || 'none'}`);
        }
    }

    async createLandRecord(ctx, surveyNumber, subdivisionNumber, area, ownerId, documentHash, officerApproval) {
        await this._assertVRO(ctx);

        const propertyId = `LAND-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;

        const surveyKey = `SURVEY-${surveyNumber}-${subdivisionNumber}`;
        const existing = await ctx.stub.getState(surveyKey);
        if (existing && existing.length > 0) {
            throw new Error(`Duplicate record: Survey ${surveyNumber}, Subdivision ${subdivisionNumber} already exists`);
        }

        const officerId = ctx.clientIdentity.getID();
        const transferHistory = [{
            fromOwner: 'GOVERNMENT',
            toOwner: ownerId,
            timestamp: new Date().toISOString(),
            txId: ctx.stub.getTxID(),
            officerId: officerId
        }];

        const landRecord = {
            propertyId,
            surveyNumber,
            subdivisionNumber,
            area: parseFloat(area),
            ownerId,
            documentHash,
            officerApproval,
            officerId,
            transferHistory,
            createdAt: new Date().toISOString()
        };

        await ctx.stub.putState(propertyId, Buffer.from(stringify(sortKeys(landRecord))));
        await ctx.stub.putState(surveyKey, Buffer.from(propertyId));

        return JSON.stringify({ propertyId, ...landRecord });
    }

    async transferLand(ctx, propertyId, newOwnerId) {
        await this._assertMRO(ctx);

        const existingBytes = await ctx.stub.getState(propertyId);
        if (!existingBytes || existingBytes.length === 0) {
            throw new Error(`Property ${propertyId} does not exist`);
        }

        const landRecord = JSON.parse(existingBytes.toString());
        const currentOwner = landRecord.ownerId;

        if (!currentOwner) {
            throw new Error('Invalid current owner');
        }

        const officerId = ctx.clientIdentity.getID();
        const transferEntry = {
            fromOwner: currentOwner,
            toOwner: newOwnerId,
            timestamp: new Date().toISOString(),
            txId: ctx.stub.getTxID(),
            officerId: officerId
        };

        landRecord.ownerId = newOwnerId;
        landRecord.transferHistory = landRecord.transferHistory || [];
        landRecord.transferHistory.push(transferEntry);

        await ctx.stub.putState(propertyId, Buffer.from(stringify(sortKeys(landRecord))));
        return JSON.stringify({ propertyId, newOwner: newOwnerId, transferEntry });
    }

    async getLandByPropertyID(ctx, propertyId) {
        const bytes = await ctx.stub.getState(propertyId);
        if (!bytes || bytes.length === 0) {
            throw new Error(`Property ${propertyId} not found`);
        }
        return bytes.toString();
    }

    async getLandBySurveyNumber(ctx, surveyNumber, subdivisionNumber) {
        const sub = subdivisionNumber || '';
        const surveyKey = `SURVEY-${surveyNumber}-${sub}`;
        const propertyIdBytes = await ctx.stub.getState(surveyKey);
        if (!propertyIdBytes || propertyIdBytes.length === 0) {
            throw new Error(`No land record for Survey ${surveyNumber}, Subdivision ${sub || 'N/A'}`);
        }
        const propertyId = propertyIdBytes.toString();
        return this.getLandByPropertyID(ctx, propertyId);
    }

    async getFullTransferHistory(ctx, propertyId) {
        const bytes = await ctx.stub.getState(propertyId);
        if (!bytes || bytes.length === 0) {
            throw new Error(`Property ${propertyId} not found`);
        }
        const landRecord = JSON.parse(bytes.toString());
        return JSON.stringify({
            propertyId,
            currentOwner: landRecord.ownerId,
            transferHistory: landRecord.transferHistory || []
        });
    }
}

module.exports = LandTokenContract;
