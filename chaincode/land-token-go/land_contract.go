package main

import (
	"encoding/json"
	"fmt"
	"log"

	"github.com/hyperledger/fabric-contract-api-go/v2/contractapi"
)

// Status constants
const (
	StatusActive          = "ACTIVE"
	StatusPendingTransfer = "PENDING_TRANSFER"
	StatusFrozen          = "FROZEN"
)

// Role constants
const (
	RoleCitizen = "Citizen"
	RoleVRO     = "VRO"
	RoleMRO     = "MRO"
	RoleAdmin   = "Admin"
)

// TransferRecord defines the structure of a transfer history entry
type TransferRecord struct {
	FromOwner  string   `json:"fromOwner"`
	ToOwner    string   `json:"toOwner"`
	Timestamp  string   `json:"timestamp"`
	ApprovedBy []string `json:"approvedBy"`
}

// Land defines the structure of a land asset
type Land struct {
	PropertyID        string           `json:"propertyID"`
	SurveyNumber      string           `json:"surveyNumber"`
	SubdivisionNumber string           `json:"subdivisionNumber"`
	OwnerID           string           `json:"ownerID"`
	Area              float64          `json:"area"`
	Jurisdiction      string           `json:"jurisdiction"`
	DocumentHash      string           `json:"documentHash"`
	Status            string           `json:"status"`
	TransferHistory   []TransferRecord `json:"transferHistory"`
	OfficerApprovals  []string         `json:"officerApprovals"`
	ProposedOwner     string           `json:"proposedOwner,omitempty"`
}

// LandContract defines the smart contract
type LandContract struct {
	contractapi.Contract
}

// DigitizeLand creates a new land asset
// Only callable by role=VRO
func (s *LandContract) DigitizeLand(ctx contractapi.TransactionContextInterface, propertyID, surveyNumber, subdivisionNumber, ownerID string, area float64, jurisdiction, documentHash string) error {
	// ABAC Enforcement
	err := verifyRole(ctx, RoleVRO)
	if err != nil {
		return err
	}

	if area <= 0 {
		return fmt.Errorf("area must be greater than zero")
	}

	exists, err := s.LandExists(ctx, propertyID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("the land %s already exists", propertyID)
	}

	land := Land{
		PropertyID:        propertyID,
		SurveyNumber:      surveyNumber,
		SubdivisionNumber: subdivisionNumber,
		OwnerID:           ownerID,
		Area:              area,
		Jurisdiction:      jurisdiction,
		DocumentHash:      documentHash,
		Status:            StatusActive,
		TransferHistory:   []TransferRecord{},
		OfficerApprovals:  []string{},
	}

	landBytes, err := json.Marshal(land)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(propertyID, landBytes)
}

// InitiateTransfer sets the land status to PENDING_TRANSFER and proposes a new owner
// Callable only by current Owner
func (s *LandContract) InitiateTransfer(ctx contractapi.TransactionContextInterface, propertyID, newOwnerID string) error {
	land, err := s.GetLand(ctx, propertyID)
	if err != nil {
		return err
	}

	// ABAC Enforcement: Only current owner can initiate transfer
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}
	
	// Note: In Fabric, GetID() returns a base64 encoded X509 string.
	// For production, usually we compare a custom attribute like 'id' or the subject CN.
	// Here we assume land.OwnerID stores the identity string.
	if land.OwnerID != clientID {
		return fmt.Errorf("only the current owner can initiate a transfer. Current owner: %s, Applicant: %s", land.OwnerID, clientID)
	}

	if land.Status != StatusActive {
		return fmt.Errorf("land is not in ACTIVE status, current status: %s", land.Status)
	}

	land.Status = StatusPendingTransfer
	land.ProposedOwner = newOwnerID

	landBytes, err := json.Marshal(land)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(propertyID, landBytes)
}

// ApproveTransfer allows MROs to approve a pending transfer
// Only callable by role=MRO
// Implements multi-officer approval logic (Threshold: 2)
func (s *LandContract) ApproveTransfer(ctx contractapi.TransactionContextInterface, propertyID string) error {
	// ABAC Enforcement
	err := verifyRole(ctx, RoleMRO)
	if err != nil {
		return err
	}

	land, err := s.GetLand(ctx, propertyID)
	if err != nil {
		return err
	}

	if land.Status != StatusPendingTransfer {
		return fmt.Errorf("land is not pending transfer")
	}

	// Get MRO ID for multi-sign check
	mroID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}

	// Prevent duplicate approvals by the same officer
	for _, id := range land.OfficerApprovals {
		if id == mroID {
			return fmt.Errorf("this officer has already approved this transfer")
		}
	}

	land.OfficerApprovals = append(land.OfficerApprovals, mroID)

	// After required threshold (e.g., 2 approvals), finalize transfer
	if len(land.OfficerApprovals) >= 2 {
		timestamp, err := ctx.GetStub().GetTxTimestamp()
		if err != nil {
			return fmt.Errorf("failed to get transaction timestamp: %v", err)
		}

		record := TransferRecord{
			FromOwner:  land.OwnerID,
			ToOwner:    land.ProposedOwner,
			Timestamp:  timestamp.AsTime().String(),
			ApprovedBy: land.OfficerApprovals,
		}

		land.TransferHistory = append(land.TransferHistory, record)
		land.OwnerID = land.ProposedOwner
		land.ProposedOwner = ""
		land.Status = StatusActive
		land.OfficerApprovals = []string{} // Reset approvals for next transfer
	}

	landBytes, err := json.Marshal(land)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(propertyID, landBytes)
}

// SplitSubdivision allows partial land sale
// Only callable by current Owner
func (s *LandContract) SplitSubdivision(ctx contractapi.TransactionContextInterface, originalPropertyID, newPropertyID string, splitArea float64, newOwnerID string) error {
	land, err := s.GetLand(ctx, originalPropertyID)
	if err != nil {
		return err
	}

	// ABAC Enforcement
	clientID, err := ctx.GetClientIdentity().GetID()
	if err != nil {
		return fmt.Errorf("failed to get client identity: %v", err)
	}
	if land.OwnerID != clientID {
		return fmt.Errorf("only the owner can split land")
	}

	if land.Status != StatusActive {
		return fmt.Errorf("land must be in ACTIVE status to split")
	}

	if splitArea <= 0 || splitArea >= land.Area {
		return fmt.Errorf("invalid split area: must be > 0 and < original area (%.2f)", land.Area)
	}

	// Ensure new property ID doesn't exist
	exists, err := s.LandExists(ctx, newPropertyID)
	if err != nil {
		return err
	}
	if exists {
		return fmt.Errorf("the property ID %s for the new subdivision already exists", newPropertyID)
	}

	// Create new land asset inheriting SurveyNumber & Jurisdiction
	newLand := Land{
		PropertyID:        newPropertyID,
		SurveyNumber:      land.SurveyNumber,
		SubdivisionNumber: land.SubdivisionNumber + "/S-1", // Automatic subdivision incrementing logic can be complex; using suffix here
		OwnerID:           newOwnerID,
		Area:              splitArea,
		Jurisdiction:      land.Jurisdiction,
		DocumentHash:      land.DocumentHash,
		Status:            StatusActive,
		TransferHistory:   []TransferRecord{},
		OfficerApprovals:  []string{},
	}

	// Reduce area of original land
	land.Area -= splitArea

	// Update original
	landBytes, err := json.Marshal(land)
	if err != nil {
		return err
	}
	err = ctx.GetStub().PutState(originalPropertyID, landBytes)
	if err != nil {
		return err
	}

	// Write new asset
	newLandBytes, err := json.Marshal(newLand)
	if err != nil {
		return err
	}
	return ctx.GetStub().PutState(newPropertyID, newLandBytes)
}

// FreezeLand allows an admin to freeze a land asset
// Only Admin
func (s *LandContract) FreezeLand(ctx contractapi.TransactionContextInterface, propertyID string) error {
	// ABAC Enforcement
	err := verifyRole(ctx, RoleAdmin)
	if err != nil {
		return err
	}

	land, err := s.GetLand(ctx, propertyID)
	if err != nil {
		return err
	}

	land.Status = StatusFrozen

	landBytes, err := json.Marshal(land)
	if err != nil {
		return err
	}

	return ctx.GetStub().PutState(propertyID, landBytes)
}

// GetLand returns the land asset with given propertyID
func (s *LandContract) GetLand(ctx contractapi.TransactionContextInterface, propertyID string) (*Land, error) {
	landBytes, err := ctx.GetStub().GetState(propertyID)
	if err != nil {
		return nil, fmt.Errorf("failed to read from world state: %v", err)
	}
	if landBytes == nil {
		return nil, fmt.Errorf("the land %s does not exist", propertyID)
	}

	var land Land
	err = json.Unmarshal(landBytes, &land)
	if err != nil {
		return nil, err
	}

	return &land, nil
}

// LandExists returns true when asset with given ID exists in world state
func (s *LandContract) LandExists(ctx contractapi.TransactionContextInterface, propertyID string) (bool, error) {
	landBytes, err := ctx.GetStub().GetState(propertyID)
	if err != nil {
		return false, fmt.Errorf("failed to read from world state: %v", err)
	}

	return landBytes != nil, nil
}

// GetLandHistory returns the full transaction history for a land asset
func (s *LandContract) GetLandHistory(ctx contractapi.TransactionContextInterface, propertyID string) ([]interface{}, error) {
	resultsIterator, err := ctx.GetStub().GetHistoryForKey(propertyID)
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var records []interface{}
	for resultsIterator.HasNext() {
		response, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var land Land
		if len(response.Value) > 0 {
			err = json.Unmarshal(response.Value, &land)
			if err != nil {
				return nil, err
			}
		} else {
			land = Land{PropertyID: propertyID}
		}

		record := map[string]interface{}{
			"txId":      response.TxId,
			"timestamp": response.Timestamp.AsTime().String(),
			"isDelete":  response.IsDelete,
			"data":      land,
		}
		records = append(records, record)
	}

	return records, nil
}

// QueryBySurveyNumber performs a rich query using SurveyNumber (CouchDB selector-based)
func (s *LandContract) QueryBySurveyNumber(ctx contractapi.TransactionContextInterface, surveyNumber string) ([]*Land, error) {
	queryString := fmt.Sprintf(`{"selector":{"surveyNumber":"%s"}}`, surveyNumber)
	
	resultsIterator, err := ctx.GetStub().GetQueryResult(queryString)
	if err != nil {
		return nil, err
	}
	defer resultsIterator.Close()

	var lands []*Land
	for resultsIterator.HasNext() {
		queryResponse, err := resultsIterator.Next()
		if err != nil {
			return nil, err
		}

		var land Land
		err = json.Unmarshal(queryResponse.Value, &land)
		if err != nil {
			return nil, err
		}
		lands = append(lands, &land)
	}

	return lands, nil
}

// verifyRole helper function for Attribute-Based Access Control (ABAC)
func verifyRole(ctx contractapi.TransactionContextInterface, requiredRole string) error {
	role, found, err := ctx.GetClientIdentity().GetAttributeValue("role")
	if err != nil {
		return fmt.Errorf("failed to get attribute 'role': %v", err)
	}
	if !found {
		return fmt.Errorf("attribute 'role' not found in client identity. Ensure CA certificate has it")
	}
	if role != requiredRole {
		return fmt.Errorf("unauthorized: required role %s, actual client role %s", requiredRole, role)
	}
	return nil
}

func main() {
	landChaincode, err := contractapi.NewChaincode(&LandContract{})
	if err != nil {
		log.Panicf("Error creating land-token chaincode: %v", err)
	}

	if err := landChaincode.Start(); err != nil {
		log.Panicf("Error starting land-token chaincode: %v", err)
	}
}
