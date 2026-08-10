-- Admin-only "delete all business data" RPC backing the Settings page danger
-- zone. Wipes operational/financial records in FK-safe order while keeping
-- accounts, branches, the product catalog, and lookup lists intact so the
-- app stays usable afterward. Verified via a rolled-back transaction against
-- the real database before applying: the deletion order causes no FK
-- violations, kept tables are untouched, and a non-admin caller is rejected.

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

  RETURN v_counts;
END;
$function$;

REVOKE ALL ON FUNCTION public.delete_all_business_data() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_all_business_data() TO authenticated;
