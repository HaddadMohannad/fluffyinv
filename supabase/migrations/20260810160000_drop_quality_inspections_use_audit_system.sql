-- The quality_inspections/quality_inspection_actions feature was built
-- independently of, and duplicates, the already-shipped audit_* module
-- (audit_visits/audit_item_scores/corrective_actions, FLU-47..51). It saw
-- zero real usage (0 rows) before the audit module was discovered, so it's
-- dropped in favor of the existing, more capable system rather than
-- keeping two parallel "log a quality check" flows.

DROP FUNCTION IF EXISTS record_quality_inspection(uuid, text, numeric, inspection_status, text, jsonb);
DROP FUNCTION IF EXISTS complete_inspection_action(uuid);
DROP TABLE IF EXISTS quality_inspection_actions;
DROP TABLE IF EXISTS quality_inspections;
DROP TYPE IF EXISTS inspection_action_status;
DROP TYPE IF EXISTS inspection_status;
DELETE FROM lookup_values WHERE list_key = 'inspection_category';
DELETE FROM lookup_lists WHERE list_key = 'inspection_category';

-- Re-point delete_all_business_data() at the audit_* tables instead of the
-- now-dropped quality_inspections ones, and cover corrective_actions/
-- audit_item_scores/audit_visits too -- they're business data the same way
-- waste_records or sales_orders are, and nothing else had wired them into
-- the "delete everything" RPC yet.
CREATE OR REPLACE FUNCTION public.delete_all_business_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_counts jsonb := '{}'::jsonb;
  v_n bigint;
BEGIN
  IF coalesce(my_role() = 'admin', false) IS NOT TRUE THEN
    RAISE EXCEPTION 'only admin may delete all business data';
  END IF;

  DELETE FROM sales_lines; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('sales_lines', v_n);
  DELETE FROM import_rejects; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('import_rejects', v_n);
  DELETE FROM sales_orders; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('sales_orders', v_n);
  DELETE FROM import_files; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('import_files', v_n);
  DELETE FROM transfer_lines; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('transfer_lines', v_n);
  DELETE FROM transfers; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('transfers', v_n);
  DELETE FROM stocktake_lines; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('stocktake_lines', v_n);
  DELETE FROM stocktakes; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('stocktakes', v_n);
  DELETE FROM stock_ledger; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('stock_ledger', v_n);
  DELETE FROM production_batches; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('production_batches', v_n);
  DELETE FROM waste_records; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('waste_records', v_n);
  DELETE FROM hospitality_records; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('hospitality_records', v_n);
  DELETE FROM supplier_invoices; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('supplier_invoices', v_n);
  DELETE FROM day_closes; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('day_closes', v_n);
  DELETE FROM cash_counts; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('cash_counts', v_n);
  DELETE FROM expenses; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('expenses', v_n);
  DELETE FROM employee_cash_transactions; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('employee_cash_transactions', v_n);
  DELETE FROM corrective_actions; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('corrective_actions', v_n);
  DELETE FROM audit_item_scores; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('audit_item_scores', v_n);
  DELETE FROM audit_visits; GET DIAGNOSTICS v_n = ROW_COUNT; v_counts := v_counts || jsonb_build_object('audit_visits', v_n);

  RETURN v_counts;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_all_business_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_all_business_data() TO authenticated;
