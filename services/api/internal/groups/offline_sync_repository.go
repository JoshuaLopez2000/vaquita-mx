package groups

import (
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"github.com/JoshuaLopez2000/vaquita-mx/services/api/internal/auth"
)

func (r *Repository) SyncLocalGroups(ctx context.Context, userID string, inputs []OfflineSyncGroupInput) ([]OfflineSyncGroupResult, error) {
	if len(inputs) > 100 {
		return nil, ErrInvalid
	}
	results := make([]OfflineSyncGroupResult, 0, len(inputs))
	seen := make(map[string]bool, len(inputs))
	for _, input := range inputs {
		if seen[input.ID] {
			return nil, ErrInvalid
		}
		seen[input.ID] = true
		if err := r.syncLocalGroup(ctx, userID, input); err != nil {
			return nil, err
		}
		results = append(results, OfflineSyncGroupResult{
			LocalGroupID:  input.ID,
			RemoteGroupID: input.ID,
		})
	}
	return results, nil
}

func (r *Repository) syncLocalGroup(ctx context.Context, userID string, input OfflineSyncGroupInput) error {
	input.Name = strings.TrimSpace(input.Name)
	input.Emoji = strings.TrimSpace(input.Emoji)
	if !validSyncID(input.ID) || len(input.Members) == 0 || len(input.Members) > 200 ||
		len(input.Expenses) > 2000 || len(input.ExpenseReversals) > 2000 ||
		len(input.Settlements) > 2000 || len(input.SettlementReversals) > 2000 ||
		len(input.Name) < 2 || input.Emoji == "" ||
		(input.Visibility != "personal" && input.Visibility != "shared") {
		return ErrInvalid
	}
	tx, err := r.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()
	if err = lockGroup(ctx, tx, "offline-sync:"+userID+":"+input.ID); err != nil {
		return err
	}

	var groupID string
	err = tx.QueryRowContext(ctx,
		`SELECT group_id FROM offline_sync_groups WHERE user_id=$1 AND local_group_id=$2`,
		userID, input.ID).Scan(&groupID)
	created := errors.Is(err, sql.ErrNoRows)
	newGroup := false
	if err != nil && !created {
		return err
	}
	if created {
		groupID = input.ID
		var existingOwner sql.NullString
		err = tx.QueryRowContext(ctx,
			`SELECT owner_id FROM expense_groups WHERE id=$1`,
			groupID).Scan(&existingOwner)
		switch {
		case errors.Is(err, sql.ErrNoRows):
			if !strings.HasPrefix(input.ID, "local_group_") {
				return ErrNotFound
			}
			newGroup = true
			_, err = tx.ExecContext(ctx,
				`INSERT INTO expense_groups(id,name,emoji,owner_id,visibility,salary_split_enabled) VALUES($1,$2,$3,$4,$5,false)`,
				groupID, input.Name, input.Emoji, userID, input.Visibility)
			if err != nil {
				return err
			}
			if err = r.owner(ctx, tx, groupID, userID); err != nil {
				return err
			}
			if err := insertSyncGroupLink(ctx, tx, userID, input.ID, groupID); err != nil {
				return err
			}
			if input.Members[0].ID == "" {
				return ErrInvalid
			}
			if err = addSyncMemberLink(ctx, tx, userID, input.ID, input.Members[0].ID, userID); err != nil {
				return err
			}
			if err = addSyncMemberLink(ctx, tx, userID, input.ID, userID, userID); err != nil {
				return err
			}
		case err == nil:
			var acceptedMember bool
			if err = tx.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL)`,
				groupID, userID).Scan(&acceptedMember); err != nil {
				return err
			}
			if !acceptedMember {
				return ErrNotFound
			}
			if _, err = tx.ExecContext(ctx,
				`INSERT INTO offline_sync_groups(user_id,local_group_id,group_id) VALUES($1,$2,$3)`,
				userID, input.ID, groupID); err != nil {
				return err
			}
		default:
			return err
		}
		if err := insertSyncGroupLink(ctx, tx, userID, input.ID, groupID); err != nil {
			return err
		}
	}

	var role string
	if err = tx.QueryRowContext(ctx,
		`SELECT role FROM group_members WHERE group_id=$1 AND user_id=$2 AND removed_at IS NULL AND accepted AND declined_at IS NULL`,
		groupID, userID).Scan(&role); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrNotFound
		}
		return err
	}
	isOwner := role == RoleOwner
	if isOwner {
		if _, err = tx.ExecContext(ctx,
			`UPDATE expense_groups SET name=$1,emoji=$2,visibility=$3,salary_split_enabled=false WHERE id=$4`,
			input.Name, input.Emoji, input.Visibility, groupID); err != nil {
			return err
		}
	}

	memberIDs := make(map[string]string, len(input.Members))
	seenMembers := make(map[string]bool, len(input.Members))
	group, err := Ledger(ctx, groupID, tx)
	if err != nil {
		return err
	}
	nextPosition := len(group.Members)
	for position, member := range input.Members {
		if !validSyncID(member.ID) || seenMembers[member.ID] || strings.TrimSpace(member.Name) == "" {
			return ErrInvalid
		}
		seenMembers[member.ID] = true
		var remoteMemberID string
		err = tx.QueryRowContext(ctx,
			`SELECT member_id FROM offline_sync_members WHERE user_id=$1 AND local_group_id=$2 AND local_member_id=$3`,
			userID, input.ID, member.ID).Scan(&remoteMemberID)
		if errors.Is(err, sql.ErrNoRows) {
			if newGroup && position == 0 {
				remoteMemberID = userID
			} else if member.ID == userID {
				remoteMemberID = userID
			} else {
				var exists bool
				err = tx.QueryRowContext(ctx,
					`SELECT EXISTS(SELECT 1 FROM group_members WHERE group_id=$1 AND member_id=$2 AND removed_at IS NULL)`,
					groupID, member.ID).Scan(&exists)
				if err != nil {
					return err
				}
				if exists {
					remoteMemberID = member.ID
				} else {
					if !isOwner {
						return ErrNotFound
					}
					if err = r.memberWithIDAllowUnregistered(ctx, tx, groupID, nextPosition, member.ID,
						MemberInput{Name: member.Name, Phone: member.Phone}, input.Visibility == "shared", true); err != nil {
						return err
					}
					nextPosition++
					remoteMemberID = member.ID
				}
			}
			if err = addSyncMemberLink(ctx, tx, userID, input.ID, member.ID, remoteMemberID); err != nil {
				return err
			}
		} else if err != nil {
			return err
		}
		memberIDs[member.ID] = remoteMemberID
		if remoteMemberID == userID {
			memberIDs[userID] = userID
		}
		if isOwner {
			phone := ""
			if strings.TrimSpace(member.Phone) != "" {
				var ok bool
				phone, ok = auth.NormalizePhone(member.Phone)
				if !ok {
					return ErrInvalid
				}
			}
			if remoteMemberID != userID {
				if _, err = tx.ExecContext(ctx,
					`UPDATE members SET name=$1,phone=NULLIF($2,'') WHERE id=$3`,
					strings.TrimSpace(member.Name), phone, remoteMemberID); err != nil {
					return err
				}
				if member.Active {
					if _, err = tx.ExecContext(ctx,
						`UPDATE group_members SET removed_at=NULL WHERE group_id=$1 AND member_id=$2`,
						groupID, remoteMemberID); err != nil {
						return err
					}
				} else {
					if _, err = tx.ExecContext(ctx,
						`UPDATE group_members SET removed_at=COALESCE(removed_at,now()) WHERE group_id=$1 AND member_id=$2 AND role <> 'owner'`,
						groupID, remoteMemberID); err != nil {
						return err
					}
				}
			}
			if _, err = tx.ExecContext(ctx,
				`UPDATE group_members SET salary_sharing=$1 WHERE group_id=$2 AND member_id=$3`,
				member.SalarySharing, groupID, remoteMemberID); err != nil {
				return err
			}
		}
	}
	if isOwner && input.SalarySplitEnabled {
		if !salaryReady(ctx, tx, groupID) {
			return ErrInvalid
		}
		if _, err = tx.ExecContext(ctx,
			`UPDATE expense_groups SET salary_split_enabled=true WHERE id=$1`,
			groupID); err != nil {
			return err
		}
	}

	if len(input.Expenses) > 0 || len(input.ExpenseReversals) > 0 ||
		len(input.Settlements) > 0 || len(input.SettlementReversals) > 0 {
		if err = lockGroup(ctx, tx, groupID); err != nil {
			return err
		}
	}

	type syncEvent struct {
		kind      int
		index     int
		createdAt time.Time
	}
	events := make([]syncEvent, 0, len(input.Expenses)+len(input.ExpenseReversals)+len(input.Settlements)+len(input.SettlementReversals))

	seenExpenses := make(map[string]bool, len(input.Expenses))
	for i, localExpense := range input.Expenses {
		if !validSyncID(localExpense.ID) || seenExpenses[localExpense.ID] || localExpense.CreatedAt.IsZero() {
			return ErrInvalid
		}
		seenExpenses[localExpense.ID] = true
		kind := 0
		if strings.TrimSpace(localExpense.ReplacesExpenseID) != "" {
			kind = 4
		}
		events = append(events, syncEvent{kind: kind, index: i, createdAt: localExpense.CreatedAt})
	}
	seenSettlements := make(map[string]bool, len(input.Settlements))
	for i, localSettlement := range input.Settlements {
		if !validSyncID(localSettlement.ID) || seenSettlements[localSettlement.ID] ||
			localSettlement.AmountCents <= 0 || localSettlement.CreatedAt.IsZero() {
			return ErrInvalid
		}
		seenSettlements[localSettlement.ID] = true
		kind := 1
		if strings.TrimSpace(localSettlement.ReplacesSettlementID) != "" {
			kind = 5
		}
		events = append(events, syncEvent{kind: kind, index: i, createdAt: localSettlement.CreatedAt})
	}
	seenExpenseReversals := make(map[string]bool, len(input.ExpenseReversals))
	for i, localReversal := range input.ExpenseReversals {
		if !validSyncID(localReversal.ID) || !validSyncID(localReversal.OriginalExpenseID) ||
			seenExpenseReversals[localReversal.ID] || localReversal.CreatedAt.IsZero() {
			return ErrInvalid
		}
		seenExpenseReversals[localReversal.ID] = true
		events = append(events, syncEvent{kind: 2, index: i, createdAt: localReversal.CreatedAt})
	}
	seenSettlementReversals := make(map[string]bool, len(input.SettlementReversals))
	for i, localReversal := range input.SettlementReversals {
		if !validSyncID(localReversal.ID) || !validSyncID(localReversal.OriginalSettlementID) ||
			seenSettlementReversals[localReversal.ID] || localReversal.CreatedAt.IsZero() {
			return ErrInvalid
		}
		seenSettlementReversals[localReversal.ID] = true
		events = append(events, syncEvent{kind: 3, index: i, createdAt: localReversal.CreatedAt})
	}

	sort.Slice(events, func(i, j int) bool {
		if !events[i].createdAt.Equal(events[j].createdAt) {
			return events[i].createdAt.Before(events[j].createdAt)
		}
		if events[i].kind != events[j].kind {
			return events[i].kind < events[j].kind
		}
		return events[i].index < events[j].index
	})

	for _, event := range events {
		switch event.kind {
		case 0, 4:
			localExpense := input.Expenses[event.index]
			hash, err := syncPayloadHash(localExpense)
			if err != nil {
				return err
			}
			exists, err := checkSyncEntry(ctx, tx, userID, input.ID, "expense", localExpense.ID, hash)
			if err != nil {
				return err
			}
			if exists {
				continue
			}
			if !newGroup && !strings.HasPrefix(localExpense.ID, "local_expense_") {
				continue
			}
			var payerID string
			if len(localExpense.Payers) == 0 {
				payerID = memberIDs[localExpense.PayerID]
			} else {
				payerID = memberIDs[localExpense.Payers[0].MemberID]
			}
			if payerID == "" {
				return ErrInvalid
			}
			payers := make([]ExpensePayer, 0, len(localExpense.Payers))
			for _, payer := range localExpense.Payers {
				memberID := memberIDs[payer.MemberID]
				if memberID == "" {
					return ErrInvalid
				}
				payers = append(payers, ExpensePayer{MemberID: memberID, AmountCents: payer.AmountCents})
			}
			participants := make([]string, 0, len(localExpense.ParticipantIDs))
			for _, localMemberID := range localExpense.ParticipantIDs {
				memberID := memberIDs[localMemberID]
				if memberID == "" {
					return ErrInvalid
				}
				participants = append(participants, memberID)
			}
			shares := make([]ExpenseShare, 0, len(localExpense.Shares))
			for _, localMemberID := range localExpense.ParticipantIDs {
				if amount, ok := localExpense.Shares[localMemberID]; ok && localExpense.SplitMode == "exact" {
					shares = append(shares, ExpenseShare{MemberID: memberIDs[localMemberID], AmountCents: amount})
				}
			}
			var percentages []ExpensePercentage
			if localExpense.SplitMode == "percentage" {
				if len(localExpense.Percentages) != len(localExpense.ParticipantIDs) {
					return ErrInvalid
				}
				percentages = make([]ExpensePercentage, 0, len(localExpense.ParticipantIDs))
				for _, localMemberID := range localExpense.ParticipantIDs {
					bps, ok := localExpense.Percentages[localMemberID]
					if !ok {
						return ErrInvalid
					}
					percentages = append(percentages, ExpensePercentage{
						MemberID:      memberIDs[localMemberID],
						PercentageBps: bps,
					})
				}
			} else if len(localExpense.Percentages) != 0 {
				return ErrInvalid
			}
			replacesExpenseID := strings.TrimSpace(localExpense.ReplacesExpenseID)
			if replacesExpenseID != "" {
				if err = validateExpenseReplacement(ctx, tx, groupID, replacesExpenseID); err != nil {
					return err
				}
			}
			splitOverpayment := localExpense.SplitOverpayment
			expenseInput := AddExpenseInput{
				Description:       localExpense.Description,
				AmountCents:       localExpense.AmountCents,
				PayerID:           payerID,
				Payers:            payers,
				ParticipantIDs:    participants,
				SplitMode:         localExpense.SplitMode,
				Shares:            shares,
				Percentages:       percentages,
				SplitOverpayment:  &splitOverpayment,
				ReplacesExpenseID: replacesExpenseID,
			}
			group, err = Ledger(ctx, groupID, tx)
			if err != nil {
				return err
			}
			if err = prepareExpense(group, &expenseInput); err != nil {
				return err
			}
			if err = insertExpense(ctx, tx, groupID, localExpense.ID, expenseInput, localExpense.CreatedAt); err != nil {
				return err
			}
			if err = addSyncEntry(ctx, tx, userID, input.ID, "expense", localExpense.ID, hash); err != nil {
				return err
			}

		case 1, 5:
			localSettlement := input.Settlements[event.index]
			hash, err := syncPayloadHash(localSettlement)
			if err != nil {
				return err
			}
			exists, err := checkSyncEntry(ctx, tx, userID, input.ID, "settlement", localSettlement.ID, hash)
			if err != nil {
				return err
			}
			if exists {
				continue
			}
			if !newGroup && !strings.HasPrefix(localSettlement.ID, "local_settlement_") {
				continue
			}
			fromID := memberIDs[localSettlement.FromMemberID]
			toID := memberIDs[localSettlement.ToMemberID]
			if fromID == "" || toID == "" || fromID == toID || (fromID != userID && toID != userID) {
				return ErrInvalid
			}
			replacesSettlementID := strings.TrimSpace(localSettlement.ReplacesSettlementID)
			if replacesSettlementID != "" {
				if err = validateSettlementReplacement(ctx, tx, groupID, replacesSettlementID); err != nil {
					return err
				}
			}
			group, err = Ledger(ctx, groupID, tx)
			if err != nil {
				return err
			}
			var outstanding int64
			for _, relation := range group.PaymentRelations {
				if relation.FromMemberID == fromID && relation.ToMemberID == toID {
					outstanding = relation.AmountCents
					break
				}
			}
			if localSettlement.AmountCents > outstanding {
				return ErrOverpayment
			}
			var replacesSettlement sql.NullString
			if replacesSettlementID != "" {
				replacesSettlement = sql.NullString{String: replacesSettlementID, Valid: true}
			}
			if _, err = tx.ExecContext(ctx,
				`INSERT INTO settlements(id,group_id,from_member_id,to_member_id,amount_cents,replaces_settlement_id,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)`,
				localSettlement.ID, groupID, fromID, toID, localSettlement.AmountCents, replacesSettlement, localSettlement.CreatedAt); err != nil {
				return err
			}
			if err = addSyncEntry(ctx, tx, userID, input.ID, "settlement", localSettlement.ID, hash); err != nil {
				return err
			}

		case 2:
			localReversal := input.ExpenseReversals[event.index]
			hash, err := syncPayloadHash(localReversal)
			if err != nil {
				return err
			}
			exists, err := checkSyncEntry(ctx, tx, userID, input.ID, "expense_reversal", localReversal.ID, hash)
			if err != nil {
				return err
			}
			if exists {
				continue
			}
			if !newGroup && !strings.HasPrefix(localReversal.ID, "local_expense_reversal_") {
				continue
			}
			if input.Visibility == "personal" && !isOwner {
				return ErrNotFound
			}
			actorMemberID := memberIDs[localReversal.ActorMemberID]
			if actorMemberID == "" {
				actorMemberID = userID
			}
			reason, err := validateReversalReason(localReversal.Reason)
			if err != nil {
				return err
			}
			var expenseExists bool
			if err = tx.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM expenses WHERE id=$1 AND group_id=$2)`,
				localReversal.OriginalExpenseID, groupID).Scan(&expenseExists); err != nil {
				return err
			}
			if !expenseExists {
				return ErrNotFound
			}
			var alreadyReversed bool
			if err = tx.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM expense_reversals WHERE original_expense_id=$1)`,
				localReversal.OriginalExpenseID).Scan(&alreadyReversed); err != nil {
				return err
			}
			if alreadyReversed {
				return ErrAlreadyReversed
			}
			if _, err = tx.ExecContext(ctx,
				`INSERT INTO expense_reversals(id,group_id,original_expense_id,actor_user_id,actor_member_id,reason,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)`,
				localReversal.ID, groupID, localReversal.OriginalExpenseID, userID, actorMemberID, reason, localReversal.CreatedAt); err != nil {
				return err
			}
			if err = addSyncEntry(ctx, tx, userID, input.ID, "expense_reversal", localReversal.ID, hash); err != nil {
				return err
			}

		case 3:
			localReversal := input.SettlementReversals[event.index]
			hash, err := syncPayloadHash(localReversal)
			if err != nil {
				return err
			}
			exists, err := checkSyncEntry(ctx, tx, userID, input.ID, "settlement_reversal", localReversal.ID, hash)
			if err != nil {
				return err
			}
			if exists {
				continue
			}
			if !newGroup && !strings.HasPrefix(localReversal.ID, "local_settlement_reversal_") {
				continue
			}
			if input.Visibility == "personal" && !isOwner {
				return ErrNotFound
			}
			actorMemberID := memberIDs[localReversal.ActorMemberID]
			if actorMemberID == "" {
				actorMemberID = userID
			}
			reason, err := validateReversalReason(localReversal.Reason)
			if err != nil {
				return err
			}
			var toMemberID string
			err = tx.QueryRowContext(ctx,
				`SELECT to_member_id FROM settlements WHERE id=$1 AND group_id=$2`,
				localReversal.OriginalSettlementID, groupID).Scan(&toMemberID)
			if errors.Is(err, sql.ErrNoRows) {
				return ErrNotFound
			}
			if err != nil {
				return err
			}
			if input.Visibility == "shared" && !isOwner && toMemberID != actorMemberID {
				return ErrNotFound
			}
			var alreadyReversed bool
			if err = tx.QueryRowContext(ctx,
				`SELECT EXISTS(SELECT 1 FROM settlement_reversals WHERE original_settlement_id=$1)`,
				localReversal.OriginalSettlementID).Scan(&alreadyReversed); err != nil {
				return err
			}
			if alreadyReversed {
				return ErrAlreadyReversed
			}
			if _, err = tx.ExecContext(ctx,
				`INSERT INTO settlement_reversals(id,group_id,original_settlement_id,actor_user_id,actor_member_id,reason,created_at) VALUES($1,$2,$3,$4,$5,$6,$7)`,
				localReversal.ID, groupID, localReversal.OriginalSettlementID, userID, actorMemberID, reason, localReversal.CreatedAt); err != nil {
				return err
			}
			if err = addSyncEntry(ctx, tx, userID, input.ID, "settlement_reversal", localReversal.ID, hash); err != nil {
				return err
			}
		}
	}

	return tx.Commit()
}

func insertSyncGroupLink(ctx context.Context, tx *sql.Tx, userID, localGroupID, groupID string) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO offline_sync_groups(user_id,local_group_id,group_id) VALUES($1,$2,$3) ON CONFLICT(user_id,local_group_id) DO NOTHING`,
		userID, localGroupID, groupID)
	return err
}

func addSyncMemberLink(ctx context.Context, tx *sql.Tx, userID, localGroupID, localMemberID, memberID string) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO offline_sync_members(user_id,local_group_id,local_member_id,member_id) VALUES($1,$2,$3,$4) ON CONFLICT(user_id,local_group_id,local_member_id) DO NOTHING`,
		userID, localGroupID, localMemberID, memberID)
	return err
}

func checkSyncEntry(ctx context.Context, tx *sql.Tx, userID, localGroupID, entityType, entityID, hash string) (bool, error) {
	var existingHash string
	err := tx.QueryRowContext(ctx,
		`SELECT payload_hash FROM offline_sync_entries WHERE user_id=$1 AND local_group_id=$2 AND entity_type=$3 AND local_entity_id=$4`,
		userID, localGroupID, entityType, entityID).Scan(&existingHash)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	if existingHash != hash {
		return false, ErrSyncConflict
	}
	return true, nil
}

func addSyncEntry(ctx context.Context, tx *sql.Tx, userID, localGroupID, entityType, entityID, hash string) error {
	_, err := tx.ExecContext(ctx,
		`INSERT INTO offline_sync_entries(user_id,local_group_id,entity_type,local_entity_id,payload_hash) VALUES($1,$2,$3,$4,$5)`,
		userID, localGroupID, entityType, entityID, hash)
	return err
}

func syncPayloadHash(value any) (string, error) {
	encoded, err := json.Marshal(value)
	if err != nil {
		return "", err
	}
	hash := sha256.Sum256(encoded)
	return hex.EncodeToString(hash[:]), nil
}

func validSyncID(id string) bool {
	return id != "" && id == strings.TrimSpace(id) && len(id) <= 120 && !strings.ContainsAny(id, "\x00\r\n")
}
