export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[];

export type Database = {
  // Allows to automatically instantiate createClient with right options
  // instead of createClient<Database, { PostgrestVersion: 'XX' }>(URL, KEY)
  __InternalSupabase: {
    PostgrestVersion: "14.5";
  };
  public: {
    Tables: {
      addon_categories: {
        Row: {
          active: boolean;
          created_at: string;
          foodics_id: string | null;
          id: string;
          is_ready: boolean;
          name_ar: string;
          name_en: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          foodics_id?: string | null;
          id?: string;
          is_ready?: boolean;
          name_ar: string;
          name_en: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          foodics_id?: string | null;
          id?: string;
          is_ready?: boolean;
          name_ar?: string;
          name_en?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      addon_category_options: {
        Row: {
          addon_category_id: string;
          product_id: string;
          sort_order: number;
        };
        Insert: {
          addon_category_id: string;
          product_id: string;
          sort_order?: number;
        };
        Update: {
          addon_category_id?: string;
          product_id?: string;
          sort_order?: number;
        };
        Relationships: [
          {
            foreignKeyName: "addon_category_options_addon_category_id_fkey";
            columns: ["addon_category_id"];
            isOneToOne: false;
            referencedRelation: "addon_categories";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "addon_category_options_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      alert_settings: {
        Row: {
          id: boolean;
          stocktake_alert_threshold_jod: number;
          updated_at: string;
          updated_by: string | null;
          waste_alert_threshold_jod: number;
        };
        Insert: {
          id?: boolean;
          stocktake_alert_threshold_jod?: number;
          updated_at?: string;
          updated_by?: string | null;
          waste_alert_threshold_jod?: number;
        };
        Update: {
          id?: boolean;
          stocktake_alert_threshold_jod?: number;
          updated_at?: string;
          updated_by?: string | null;
          waste_alert_threshold_jod?: number;
        };
        Relationships: [
          {
            foreignKeyName: "alert_settings_updated_by_fkey";
            columns: ["updated_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_categories: {
        Row: {
          active: boolean;
          created_at: string;
          id: string;
          name: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      audit_item_scores: {
        Row: {
          created_at: string;
          evidence_urls: string[] | null;
          id: string;
          item_id: string;
          note: string | null;
          score: number | null;
          visit_id: string;
        };
        Insert: {
          created_at?: string;
          evidence_urls?: string[] | null;
          id?: string;
          item_id: string;
          note?: string | null;
          score?: number | null;
          visit_id: string;
        };
        Update: {
          created_at?: string;
          evidence_urls?: string[] | null;
          id?: string;
          item_id?: string;
          note?: string | null;
          score?: number | null;
          visit_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "audit_item_scores_item_id_fkey";
            columns: ["item_id"];
            isOneToOne: false;
            referencedRelation: "audit_items";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_item_scores_visit_id_fkey";
            columns: ["visit_id"];
            isOneToOne: false;
            referencedRelation: "audit_visits";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_item_scores_visit_id_fkey";
            columns: ["visit_id"];
            isOneToOne: false;
            referencedRelation: "v_audit_visit_scores";
            referencedColumns: ["visit_id"];
          },
        ];
      };
      audit_items: {
        Row: {
          active: boolean;
          category_id: string;
          created_at: string;
          definition: string | null;
          id: string;
          label: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          category_id: string;
          created_at?: string;
          definition?: string | null;
          id?: string;
          label: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          category_id?: string;
          created_at?: string;
          definition?: string | null;
          id?: string;
          label?: string;
          sort_order?: number;
        };
        Relationships: [
          {
            foreignKeyName: "audit_items_category_id_fkey";
            columns: ["category_id"];
            isOneToOne: false;
            referencedRelation: "audit_categories";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_location_grants: {
        Row: {
          created_at: string;
          id: string;
          location_id: string;
          profile_id: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          location_id: string;
          profile_id: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          location_id?: string;
          profile_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "audit_location_grants_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_location_grants_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_visits: {
        Row: {
          auditor_id: string | null;
          created_at: string;
          id: string;
          location_id: string;
          notes: string | null;
          visit_date: string;
        };
        Insert: {
          auditor_id?: string | null;
          created_at?: string;
          id?: string;
          location_id: string;
          notes?: string | null;
          visit_date?: string;
        };
        Update: {
          auditor_id?: string | null;
          created_at?: string;
          id?: string;
          location_id?: string;
          notes?: string | null;
          visit_date?: string;
        };
        Relationships: [
          {
            foreignKeyName: "audit_visits_auditor_id_fkey";
            columns: ["auditor_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_visits_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      cash_counts: {
        Row: {
          count_date: string;
          counted_amount: number;
          created_at: string;
          created_by: string | null;
          location_id: string;
        };
        Insert: {
          count_date: string;
          counted_amount: number;
          created_at?: string;
          created_by?: string | null;
          location_id: string;
        };
        Update: {
          count_date?: string;
          counted_amount?: number;
          created_at?: string;
          created_by?: string | null;
          location_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "cash_counts_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "cash_counts_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      corrective_actions: {
        Row: {
          action_required: string | null;
          actual_cost: number | null;
          created_at: string;
          created_by: string | null;
          description: string;
          due_date: string | null;
          estimated_cost: number | null;
          id: string;
          item_id: string | null;
          location_id: string;
          owner: string | null;
          recheck_date: string | null;
          recheck_result: string | null;
          status: string;
          visit_id: string | null;
        };
        Insert: {
          action_required?: string | null;
          actual_cost?: number | null;
          created_at?: string;
          created_by?: string | null;
          description: string;
          due_date?: string | null;
          estimated_cost?: number | null;
          id?: string;
          item_id?: string | null;
          location_id: string;
          owner?: string | null;
          recheck_date?: string | null;
          recheck_result?: string | null;
          status?: string;
          visit_id?: string | null;
        };
        Update: {
          action_required?: string | null;
          actual_cost?: number | null;
          created_at?: string;
          created_by?: string | null;
          description?: string;
          due_date?: string | null;
          estimated_cost?: number | null;
          id?: string;
          item_id?: string | null;
          location_id?: string;
          owner?: string | null;
          recheck_date?: string | null;
          recheck_result?: string | null;
          status?: string;
          visit_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "corrective_actions_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "corrective_actions_item_id_fkey";
            columns: ["item_id"];
            isOneToOne: false;
            referencedRelation: "audit_items";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "corrective_actions_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "corrective_actions_visit_id_fkey";
            columns: ["visit_id"];
            isOneToOne: false;
            referencedRelation: "audit_visits";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "corrective_actions_visit_id_fkey";
            columns: ["visit_id"];
            isOneToOne: false;
            referencedRelation: "v_audit_visit_scores";
            referencedColumns: ["visit_id"];
          },
        ];
      };
      day_closes: {
        Row: {
          close_date: string;
          closed_at: string;
          closed_by: string | null;
          location_id: string;
          reopen_reason: string | null;
          reopened_at: string | null;
          reopened_by: string | null;
        };
        Insert: {
          close_date: string;
          closed_at?: string;
          closed_by?: string | null;
          location_id: string;
          reopen_reason?: string | null;
          reopened_at?: string | null;
          reopened_by?: string | null;
        };
        Update: {
          close_date?: string;
          closed_at?: string;
          closed_by?: string | null;
          location_id?: string;
          reopen_reason?: string | null;
          reopened_at?: string | null;
          reopened_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "day_closes_closed_by_fkey";
            columns: ["closed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "day_closes_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "day_closes_reopened_by_fkey";
            columns: ["reopened_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      employee_cash_transactions: {
        Row: {
          amount: number;
          created_at: string;
          created_by: string | null;
          employee_id: string;
          id: string;
          location_id: string;
          note: string | null;
          transaction_date: string;
          type: string;
        };
        Insert: {
          amount: number;
          created_at?: string;
          created_by?: string | null;
          employee_id: string;
          id?: string;
          location_id: string;
          note?: string | null;
          transaction_date: string;
          type: string;
        };
        Update: {
          amount?: number;
          created_at?: string;
          created_by?: string | null;
          employee_id?: string;
          id?: string;
          location_id?: string;
          note?: string | null;
          transaction_date?: string;
          type?: string;
        };
        Relationships: [
          {
            foreignKeyName: "employee_cash_transactions_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "employee_cash_transactions_employee_id_fkey";
            columns: ["employee_id"];
            isOneToOne: false;
            referencedRelation: "employees";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "employee_cash_transactions_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      employees: {
        Row: {
          active: boolean;
          created_at: string;
          id: string;
          location_id: string;
          name: string;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          id?: string;
          location_id: string;
          name: string;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          id?: string;
          location_id?: string;
          name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "employees_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      expenses: {
        Row: {
          amount: number;
          category: string;
          created_at: string;
          created_by: string | null;
          description: string | null;
          expense_date: string;
          id: string;
          location_id: string;
        };
        Insert: {
          amount: number;
          category: string;
          created_at?: string;
          created_by?: string | null;
          description?: string | null;
          expense_date: string;
          id?: string;
          location_id: string;
        };
        Update: {
          amount?: number;
          category?: string;
          created_at?: string;
          created_by?: string | null;
          description?: string | null;
          expense_date?: string;
          id?: string;
          location_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "expenses_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "expenses_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      hospitality_limits: {
        Row: {
          limit_value: number;
          location_id: string;
          month: string;
        };
        Insert: {
          limit_value: number;
          location_id: string;
          month: string;
        };
        Update: {
          limit_value?: number;
          location_id?: string;
          month?: string;
        };
        Relationships: [
          {
            foreignKeyName: "hospitality_limits_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      hospitality_records: {
        Row: {
          created_at: string;
          created_by: string | null;
          h_type: string;
          id: string;
          location_id: string;
          notes: string | null;
          product_id: string;
          qty: number;
          value: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          h_type: string;
          id?: string;
          location_id: string;
          notes?: string | null;
          product_id: string;
          qty: number;
          value?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          h_type?: string;
          id?: string;
          location_id?: string;
          notes?: string | null;
          product_id?: string;
          qty?: number;
          value?: number;
        };
        Relationships: [
          {
            foreignKeyName: "hospitality_records_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "hospitality_records_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "hospitality_records_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      import_files: {
        Row: {
          created_at: string;
          filename: string;
          id: string;
          row_count: number | null;
          source: Database["public"]["Enums"]["sales_source"];
          storage_path: string | null;
          uploaded_by: string | null;
        };
        Insert: {
          created_at?: string;
          filename: string;
          id?: string;
          row_count?: number | null;
          source: Database["public"]["Enums"]["sales_source"];
          storage_path?: string | null;
          uploaded_by?: string | null;
        };
        Update: {
          created_at?: string;
          filename?: string;
          id?: string;
          row_count?: number | null;
          source?: Database["public"]["Enums"]["sales_source"];
          storage_path?: string | null;
          uploaded_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "import_files_uploaded_by_fkey";
            columns: ["uploaded_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      import_mappings: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: string;
          mapping: Json;
          name: string;
          source: Database["public"]["Enums"]["sales_source"];
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          mapping: Json;
          name: string;
          source: Database["public"]["Enums"]["sales_source"];
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          mapping?: Json;
          name?: string;
          source?: Database["public"]["Enums"]["sales_source"];
        };
        Relationships: [
          {
            foreignKeyName: "import_mappings_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      import_rejects: {
        Row: {
          created_at: string;
          id: string;
          import_file_id: string;
          raw_row: Json;
          reason: string;
          row_number: number | null;
        };
        Insert: {
          created_at?: string;
          id?: string;
          import_file_id: string;
          raw_row: Json;
          reason: string;
          row_number?: number | null;
        };
        Update: {
          created_at?: string;
          id?: string;
          import_file_id?: string;
          raw_row?: Json;
          reason?: string;
          row_number?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "import_rejects_import_file_id_fkey";
            columns: ["import_file_id"];
            isOneToOne: false;
            referencedRelation: "import_files";
            referencedColumns: ["id"];
          },
        ];
      };
      location_aliases: {
        Row: {
          brand: string | null;
          id: string;
          location_id: string;
          source: Database["public"]["Enums"]["sales_source"];
          source_name: string;
        };
        Insert: {
          brand?: string | null;
          id?: string;
          location_id: string;
          source: Database["public"]["Enums"]["sales_source"];
          source_name: string;
        };
        Update: {
          brand?: string | null;
          id?: string;
          location_id?: string;
          source?: Database["public"]["Enums"]["sales_source"];
          source_name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "location_aliases_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      location_brands: {
        Row: {
          brand: string;
          location_id: string;
        };
        Insert: {
          brand: string;
          location_id: string;
        };
        Update: {
          brand?: string;
          location_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "location_brands_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      locations: {
        Row: {
          active: boolean;
          city: string | null;
          close_time: string | null;
          created_at: string;
          day_close_cutoff_time: string | null;
          id: string;
          name_ar: string;
          name_en: string;
          open_time: string | null;
          ownership: Database["public"]["Enums"]["ownership_type"];
          status: string;
          type: Database["public"]["Enums"]["location_type"];
        };
        Insert: {
          active?: boolean;
          city?: string | null;
          close_time?: string | null;
          created_at?: string;
          day_close_cutoff_time?: string | null;
          id?: string;
          name_ar: string;
          name_en: string;
          open_time?: string | null;
          ownership?: Database["public"]["Enums"]["ownership_type"];
          status?: string;
          type: Database["public"]["Enums"]["location_type"];
        };
        Update: {
          active?: boolean;
          city?: string | null;
          close_time?: string | null;
          created_at?: string;
          day_close_cutoff_time?: string | null;
          id?: string;
          name_ar?: string;
          name_en?: string;
          open_time?: string | null;
          ownership?: Database["public"]["Enums"]["ownership_type"];
          status?: string;
          type?: Database["public"]["Enums"]["location_type"];
        };
        Relationships: [];
      };
      lookup_lists: {
        Row: {
          created_at: string;
          list_key: string;
          name_ar: string;
          name_en: string;
        };
        Insert: {
          created_at?: string;
          list_key: string;
          name_ar: string;
          name_en: string;
        };
        Update: {
          created_at?: string;
          list_key?: string;
          name_ar?: string;
          name_en?: string;
        };
        Relationships: [];
      };
      lookup_values: {
        Row: {
          active: boolean;
          code: string;
          created_at: string;
          id: string;
          list_key: string;
          name_ar: string;
          name_en: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          code: string;
          created_at?: string;
          id?: string;
          list_key: string;
          name_ar: string;
          name_en: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          code?: string;
          created_at?: string;
          id?: string;
          list_key?: string;
          name_ar?: string;
          name_en?: string;
          sort_order?: number;
        };
        Relationships: [
          {
            foreignKeyName: "lookup_values_list_key_fkey";
            columns: ["list_key"];
            isOneToOne: false;
            referencedRelation: "lookup_lists";
            referencedColumns: ["list_key"];
          },
        ];
      };
      product_addon_categories: {
        Row: {
          addon_category_id: string;
          product_id: string;
          sort_order: number;
        };
        Insert: {
          addon_category_id: string;
          product_id: string;
          sort_order?: number;
        };
        Update: {
          addon_category_id?: string;
          product_id?: string;
          sort_order?: number;
        };
        Relationships: [
          {
            foreignKeyName: "product_addon_categories_addon_category_id_fkey";
            columns: ["addon_category_id"];
            isOneToOne: false;
            referencedRelation: "addon_categories";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_addon_categories_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      product_aliases: {
        Row: {
          created_at: string;
          id: string;
          product_id: string;
          raw_name: string;
        };
        Insert: {
          created_at?: string;
          id?: string;
          product_id: string;
          raw_name: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          product_id?: string;
          raw_name?: string;
        };
        Relationships: [
          {
            foreignKeyName: "product_aliases_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      product_categories: {
        Row: {
          active: boolean;
          created_at: string;
          id: string;
          name_ar: string;
          name_en: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name_ar: string;
          name_en: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name_ar?: string;
          name_en?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      product_group_members: {
        Row: {
          group_id: string;
          product_id: string;
        };
        Insert: {
          group_id: string;
          product_id: string;
        };
        Update: {
          group_id?: string;
          product_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "product_group_members_group_id_fkey";
            columns: ["group_id"];
            isOneToOne: false;
            referencedRelation: "product_groups";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_group_members_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      product_groups: {
        Row: {
          active: boolean;
          created_at: string;
          id: string;
          name_ar: string;
          name_en: string;
          sort_order: number;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name_ar: string;
          name_en: string;
          sort_order?: number;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name_ar?: string;
          name_en?: string;
          sort_order?: number;
        };
        Relationships: [];
      };
      product_locations: {
        Row: {
          location_id: string;
          product_id: string;
        };
        Insert: {
          location_id: string;
          product_id: string;
        };
        Update: {
          location_id?: string;
          product_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "product_locations_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "product_locations_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      production_batches: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: string;
          input_product_id: string;
          input_qty: number;
          location_id: string;
          output_product_id: string;
          output_qty: number;
          total_cost: number;
          yield_pct: number | null;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          input_product_id: string;
          input_qty: number;
          location_id: string;
          output_product_id: string;
          output_qty: number;
          total_cost: number;
          yield_pct?: number | null;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          input_product_id?: string;
          input_qty?: number;
          location_id?: string;
          output_product_id?: string;
          output_qty?: number;
          total_cost?: number;
          yield_pct?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "production_batches_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "production_batches_input_product_id_fkey";
            columns: ["input_product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "production_batches_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "production_batches_output_product_id_fkey";
            columns: ["output_product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      products: {
        Row: {
          active: boolean;
          avg_cost: number;
          brand: string | null;
          category_id: string | null;
          created_at: string;
          foodics_id: string | null;
          id: string;
          is_addon: boolean;
          is_combo: boolean;
          name_ar: string;
          name_en: string;
          recipe_unit: string | null;
          reorder_threshold: number | null;
          selling_price: number | null;
          sku: string | null;
          storage_to_recipe_factor: number;
          type: Database["public"]["Enums"]["product_type"];
          unit: Database["public"]["Enums"]["product_unit"];
        };
        Insert: {
          active?: boolean;
          avg_cost?: number;
          brand?: string | null;
          category_id?: string | null;
          created_at?: string;
          foodics_id?: string | null;
          id?: string;
          is_addon?: boolean;
          is_combo?: boolean;
          name_ar: string;
          name_en: string;
          recipe_unit?: string | null;
          reorder_threshold?: number | null;
          selling_price?: number | null;
          sku?: string | null;
          storage_to_recipe_factor?: number;
          type: Database["public"]["Enums"]["product_type"];
          unit: Database["public"]["Enums"]["product_unit"];
        };
        Update: {
          active?: boolean;
          avg_cost?: number;
          brand?: string | null;
          category_id?: string | null;
          created_at?: string;
          foodics_id?: string | null;
          id?: string;
          is_addon?: boolean;
          is_combo?: boolean;
          name_ar?: string;
          name_en?: string;
          recipe_unit?: string | null;
          reorder_threshold?: number | null;
          selling_price?: number | null;
          sku?: string | null;
          storage_to_recipe_factor?: number;
          type?: Database["public"]["Enums"]["product_type"];
          unit?: Database["public"]["Enums"]["product_unit"];
        };
        Relationships: [
          {
            foreignKeyName: "products_category_id_fkey";
            columns: ["category_id"];
            isOneToOne: false;
            referencedRelation: "product_categories";
            referencedColumns: ["id"];
          },
        ];
      };
      profile_module_grants: {
        Row: {
          module_href: string;
          profile_id: string;
        };
        Insert: {
          module_href: string;
          profile_id: string;
        };
        Update: {
          module_href?: string;
          profile_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "profile_module_grants_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      profiles: {
        Row: {
          active: boolean;
          created_at: string;
          email: string | null;
          full_name: string;
          id: string;
          location_id: string | null;
          role: Database["public"]["Enums"]["user_role"];
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          email?: string | null;
          full_name: string;
          id: string;
          location_id?: string | null;
          role: Database["public"]["Enums"]["user_role"];
        };
        Update: {
          active?: boolean;
          created_at?: string;
          email?: string | null;
          full_name?: string;
          id?: string;
          location_id?: string | null;
          role?: Database["public"]["Enums"]["user_role"];
        };
        Relationships: [
          {
            foreignKeyName: "profiles_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      recipe_lines: {
        Row: {
          component_product_id: string;
          created_at: string;
          id: string;
          parent_product_id: string;
          qty_per_unit: number;
        };
        Insert: {
          component_product_id: string;
          created_at?: string;
          id?: string;
          parent_product_id: string;
          qty_per_unit: number;
        };
        Update: {
          component_product_id?: string;
          created_at?: string;
          id?: string;
          parent_product_id?: string;
          qty_per_unit?: number;
        };
        Relationships: [
          {
            foreignKeyName: "recipe_lines_component_product_id_fkey";
            columns: ["component_product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "recipe_lines_parent_product_id_fkey";
            columns: ["parent_product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      sales_lines: {
        Row: {
          id: string;
          order_id: string;
          product_id: string | null;
          qty: number;
          raw_item_name: string | null;
          unit_price: number;
        };
        Insert: {
          id?: string;
          order_id: string;
          product_id?: string | null;
          qty: number;
          raw_item_name?: string | null;
          unit_price?: number;
        };
        Update: {
          id?: string;
          order_id?: string;
          product_id?: string | null;
          qty?: number;
          raw_item_name?: string | null;
          unit_price?: number;
        };
        Relationships: [
          {
            foreignKeyName: "sales_lines_order_id_fkey";
            columns: ["order_id"];
            isOneToOne: false;
            referencedRelation: "sales_orders";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_lines_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      sales_orders: {
        Row: {
          brand: string | null;
          commission: number;
          created_at: string;
          external_ref: string;
          gross: number;
          id: string;
          import_file_id: string | null;
          location_id: string;
          net: number;
          order_date: string;
          source: Database["public"]["Enums"]["sales_source"];
        };
        Insert: {
          brand?: string | null;
          commission?: number;
          created_at?: string;
          external_ref: string;
          gross: number;
          id?: string;
          import_file_id?: string | null;
          location_id: string;
          net: number;
          order_date: string;
          source: Database["public"]["Enums"]["sales_source"];
        };
        Update: {
          brand?: string | null;
          commission?: number;
          created_at?: string;
          external_ref?: string;
          gross?: number;
          id?: string;
          import_file_id?: string | null;
          location_id?: string;
          net?: number;
          order_date?: string;
          source?: Database["public"]["Enums"]["sales_source"];
        };
        Relationships: [
          {
            foreignKeyName: "sales_orders_import_file_id_fkey";
            columns: ["import_file_id"];
            isOneToOne: false;
            referencedRelation: "import_files";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sales_orders_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      signup_requests: {
        Row: {
          assigned_location_id: string | null;
          assigned_role: Database["public"]["Enums"]["user_role"] | null;
          decided_at: string | null;
          decided_by: string | null;
          email: string;
          full_name: string | null;
          id: string;
          requested_at: string;
          status: string;
        };
        Insert: {
          assigned_location_id?: string | null;
          assigned_role?: Database["public"]["Enums"]["user_role"] | null;
          decided_at?: string | null;
          decided_by?: string | null;
          email: string;
          full_name?: string | null;
          id: string;
          requested_at?: string;
          status?: string;
        };
        Update: {
          assigned_location_id?: string | null;
          assigned_role?: Database["public"]["Enums"]["user_role"] | null;
          decided_at?: string | null;
          decided_by?: string | null;
          email?: string;
          full_name?: string | null;
          id?: string;
          requested_at?: string;
          status?: string;
        };
        Relationships: [
          {
            foreignKeyName: "signup_requests_assigned_location_id_fkey";
            columns: ["assigned_location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "signup_requests_decided_by_fkey";
            columns: ["decided_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      stock_ledger: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: number;
          location_id: string;
          movement: Database["public"]["Enums"]["movement_type"];
          note: string | null;
          product_id: string;
          qty: number;
          reference_id: string | null;
          reference_type: string | null;
          unit_cost: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: never;
          location_id: string;
          movement: Database["public"]["Enums"]["movement_type"];
          note?: string | null;
          product_id: string;
          qty: number;
          reference_id?: string | null;
          reference_type?: string | null;
          unit_cost?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: never;
          location_id?: string;
          movement?: Database["public"]["Enums"]["movement_type"];
          note?: string | null;
          product_id?: string;
          qty?: number;
          reference_id?: string | null;
          reference_type?: string | null;
          unit_cost?: number;
        };
        Relationships: [
          {
            foreignKeyName: "stock_ledger_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_ledger_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_ledger_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      stocktake_lines: {
        Row: {
          counted_qty: number | null;
          id: string;
          product_id: string;
          stocktake_id: string;
          system_qty: number;
          unit_cost: number | null;
          variance: number | null;
        };
        Insert: {
          counted_qty?: number | null;
          id?: string;
          product_id: string;
          stocktake_id: string;
          system_qty: number;
          unit_cost?: number | null;
          variance?: number | null;
        };
        Update: {
          counted_qty?: number | null;
          id?: string;
          product_id?: string;
          stocktake_id?: string;
          system_qty?: number;
          unit_cost?: number | null;
          variance?: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "stocktake_lines_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktake_lines_stocktake_id_fkey";
            columns: ["stocktake_id"];
            isOneToOne: false;
            referencedRelation: "stocktakes";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktake_lines_stocktake_id_fkey";
            columns: ["stocktake_id"];
            isOneToOne: false;
            referencedRelation: "v_stocktake_summary";
            referencedColumns: ["id"];
          },
        ];
      };
      stocktakes: {
        Row: {
          approved_at: string | null;
          approved_by: string | null;
          id: string;
          location_id: string;
          started_at: string;
          started_by: string | null;
          status: Database["public"]["Enums"]["stocktake_status"];
        };
        Insert: {
          approved_at?: string | null;
          approved_by?: string | null;
          id?: string;
          location_id: string;
          started_at?: string;
          started_by?: string | null;
          status?: Database["public"]["Enums"]["stocktake_status"];
        };
        Update: {
          approved_at?: string | null;
          approved_by?: string | null;
          id?: string;
          location_id?: string;
          started_at?: string;
          started_by?: string | null;
          status?: Database["public"]["Enums"]["stocktake_status"];
        };
        Relationships: [
          {
            foreignKeyName: "stocktakes_approved_by_fkey";
            columns: ["approved_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktakes_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktakes_started_by_fkey";
            columns: ["started_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      supplier_invoices: {
        Row: {
          amount: number;
          created_at: string;
          due_date: string | null;
          file_path: string | null;
          id: string;
          invoice_no: string;
          location_id: string;
          review_note: string | null;
          reviewed_by: string | null;
          status: Database["public"]["Enums"]["invoice_status"];
          supplier_id: string;
          uploaded_by: string | null;
        };
        Insert: {
          amount: number;
          created_at?: string;
          due_date?: string | null;
          file_path?: string | null;
          id?: string;
          invoice_no: string;
          location_id: string;
          review_note?: string | null;
          reviewed_by?: string | null;
          status?: Database["public"]["Enums"]["invoice_status"];
          supplier_id: string;
          uploaded_by?: string | null;
        };
        Update: {
          amount?: number;
          created_at?: string;
          due_date?: string | null;
          file_path?: string | null;
          id?: string;
          invoice_no?: string;
          location_id?: string;
          review_note?: string | null;
          reviewed_by?: string | null;
          status?: Database["public"]["Enums"]["invoice_status"];
          supplier_id?: string;
          uploaded_by?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "supplier_invoices_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "supplier_invoices_reviewed_by_fkey";
            columns: ["reviewed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "supplier_invoices_supplier_id_fkey";
            columns: ["supplier_id"];
            isOneToOne: false;
            referencedRelation: "suppliers";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "supplier_invoices_uploaded_by_fkey";
            columns: ["uploaded_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      suppliers: {
        Row: {
          active: boolean;
          created_at: string;
          id: string;
          name: string;
          payment_terms: string | null;
          phone: string | null;
        };
        Insert: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name: string;
          payment_terms?: string | null;
          phone?: string | null;
        };
        Update: {
          active?: boolean;
          created_at?: string;
          id?: string;
          name?: string;
          payment_terms?: string | null;
          phone?: string | null;
        };
        Relationships: [];
      };
      transfer_lines: {
        Row: {
          id: string;
          product_id: string;
          qty: number;
          transfer_id: string;
          unit_cost: number;
        };
        Insert: {
          id?: string;
          product_id: string;
          qty: number;
          transfer_id: string;
          unit_cost?: number;
        };
        Update: {
          id?: string;
          product_id?: string;
          qty?: number;
          transfer_id?: string;
          unit_cost?: number;
        };
        Relationships: [
          {
            foreignKeyName: "transfer_lines_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "transfer_lines_transfer_id_fkey";
            columns: ["transfer_id"];
            isOneToOne: false;
            referencedRelation: "transfers";
            referencedColumns: ["id"];
          },
        ];
      };
      transfers: {
        Row: {
          completed_at: string | null;
          created_at: string;
          created_by: string | null;
          from_location: string;
          id: string;
          status: Database["public"]["Enums"]["transfer_status"];
          to_location: string;
        };
        Insert: {
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          from_location: string;
          id?: string;
          status?: Database["public"]["Enums"]["transfer_status"];
          to_location: string;
        };
        Update: {
          completed_at?: string | null;
          created_at?: string;
          created_by?: string | null;
          from_location?: string;
          id?: string;
          status?: Database["public"]["Enums"]["transfer_status"];
          to_location?: string;
        };
        Relationships: [
          {
            foreignKeyName: "transfers_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "transfers_from_location_fkey";
            columns: ["from_location"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "transfers_to_location_fkey";
            columns: ["to_location"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      waste_records: {
        Row: {
          created_at: string;
          created_by: string | null;
          id: string;
          location_id: string;
          product_id: string;
          qty: number;
          reason: string | null;
          value_lost: number;
        };
        Insert: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id: string;
          product_id: string;
          qty: number;
          reason?: string | null;
          value_lost?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          id?: string;
          location_id?: string;
          product_id?: string;
          qty?: number;
          reason?: string | null;
          value_lost?: number;
        };
        Relationships: [
          {
            foreignKeyName: "waste_records_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "waste_records_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "waste_records_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: {
      v_audit_visit_scores: {
        Row: {
          auditor_id: string | null;
          classification: string | null;
          items_failed: number | null;
          items_passed: number | null;
          items_scored: number | null;
          location_id: string | null;
          notes: string | null;
          overall_pct: number | null;
          visit_date: string | null;
          visit_id: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "audit_visits_auditor_id_fkey";
            columns: ["auditor_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "audit_visits_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      v_current_stock: {
        Row: {
          location_id: string | null;
          product_id: string | null;
          qty: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "stock_ledger_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stock_ledger_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
        ];
      };
      v_stocktake_lines: {
        Row: {
          counted_qty: number | null;
          id: string | null;
          product_id: string | null;
          stocktake_id: string | null;
          system_qty: number | null;
          unit_cost: number | null;
          variance: number | null;
        };
        Insert: {
          counted_qty?: number | null;
          id?: string | null;
          product_id?: string | null;
          stocktake_id?: string | null;
          system_qty?: never;
          unit_cost?: never;
          variance?: never;
        };
        Update: {
          counted_qty?: number | null;
          id?: string | null;
          product_id?: string | null;
          stocktake_id?: string | null;
          system_qty?: never;
          unit_cost?: never;
          variance?: never;
        };
        Relationships: [
          {
            foreignKeyName: "stocktake_lines_product_id_fkey";
            columns: ["product_id"];
            isOneToOne: false;
            referencedRelation: "products";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktake_lines_stocktake_id_fkey";
            columns: ["stocktake_id"];
            isOneToOne: false;
            referencedRelation: "stocktakes";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "stocktake_lines_stocktake_id_fkey";
            columns: ["stocktake_id"];
            isOneToOne: false;
            referencedRelation: "v_stocktake_summary";
            referencedColumns: ["id"];
          },
        ];
      };
      v_stocktake_summary: {
        Row: {
          approved_at: string | null;
          id: string | null;
          location_id: string | null;
          started_at: string | null;
          status: Database["public"]["Enums"]["stocktake_status"] | null;
          total_variance_value: number | null;
        };
        Relationships: [
          {
            foreignKeyName: "stocktakes_location_id_fkey";
            columns: ["location_id"];
            isOneToOne: false;
            referencedRelation: "locations";
            referencedColumns: ["id"];
          },
        ];
      };
      v_user_activity_log: {
        Row: {
          action: string | null;
          actor_id: string | null;
          created_at: string | null;
          detail: string | null;
          location_id: string | null;
          record_id: string | null;
          source_table: string | null;
        };
        Relationships: [];
      };
    };
    Functions: {
      apply_product_alias: {
        Args: { p_product_id: string; p_raw_name: string };
        Returns: number;
      };
      approve_signup_request: {
        Args: {
          p_location_id?: string;
          p_request_id: string;
          p_role: Database["public"]["Enums"]["user_role"];
        };
        Returns: undefined;
      };
      approve_stocktake: {
        Args: { p_stocktake_id: string };
        Returns: undefined;
      };
      cancel_transfer: { Args: { p_transfer_id: string }; Returns: undefined };
      close_day: {
        Args: { p_close_date: string; p_location_id: string };
        Returns: undefined;
      };
      complete_transfer: {
        Args: { p_transfer_id: string };
        Returns: {
          product_id: string;
          qty: number;
          unit_cost: number;
        }[];
      };
      create_transfer: {
        Args: {
          p_from_location_id: string;
          p_lines: Json;
          p_to_location_id: string;
        };
        Returns: string;
      };
      delete_all_business_data: { Args: never; Returns: Json };
      delete_audit_visit: { Args: { p_visit_id: string }; Returns: undefined };
      get_daily_closing_report: {
        Args: { p_close_date: string; p_location_id: string };
        Returns: {
          current_qty: number;
          expected_closing_qty: number;
          hospitality_qty: number;
          opening_qty: number;
          product_id: string;
          received_qty: number;
          sold_qty: number;
          waste_qty: number;
        }[];
      };
      get_smart_alerts: {
        Args: never;
        Returns: {
          alert_type: string;
          detail: Json;
          location_id: string;
          metric_value: number;
          threshold_value: number;
        }[];
      };
      has_audit_location_access: {
        Args: { p_location_id: string };
        Returns: boolean;
      };
      my_location: { Args: never; Returns: string };
      my_role: {
        Args: never;
        Returns: Database["public"]["Enums"]["user_role"];
      };
      purchase_stock: {
        Args: {
          p_location_id: string;
          p_note?: string;
          p_product_id: string;
          p_qty: number;
          p_unit_cost: number;
        };
        Returns: {
          ledger_id: number;
          new_avg_cost: number;
          new_qty: number;
        }[];
      };
      record_audit_visit: {
        Args: {
          p_location_id: string;
          p_notes?: string;
          p_scores?: Json;
          p_visit_date?: string;
        };
        Returns: string;
      };
      record_hospitality: {
        Args: {
          p_confirm_over_limit?: boolean;
          p_h_type: string;
          p_location_id: string;
          p_note?: string;
          p_product_id: string;
          p_qty: number;
        };
        Returns: {
          ledger_id: number;
          limit_value: number;
          month_usage: number;
          record_id: string;
          usage_pct: number;
          value: number;
        }[];
      };
      record_opening_stock: {
        Args: {
          p_location_id: string;
          p_note?: string;
          p_product_id: string;
          p_qty: number;
          p_unit_cost: number;
        };
        Returns: {
          ledger_id: number;
          new_avg_cost: number;
          new_qty: number;
        }[];
      };
      record_production_batch: {
        Args: {
          p_input_product_id: string;
          p_input_qty: number;
          p_location_id: string;
          p_output_product_id: string;
          p_output_qty: number;
          p_total_cost: number;
        };
        Returns: {
          batch_id: string;
          cost_per_unit: number;
          input_ledger_id: number;
          new_output_avg_cost: number;
          output_ledger_id: number;
          yield_pct: number;
        }[];
      };
      record_waste: {
        Args: {
          p_location_id: string;
          p_product_id: string;
          p_qty: number;
          p_reason: string;
        };
        Returns: {
          ledger_id: number;
          record_id: string;
          value_lost: number;
        }[];
      };
      reject_signup_request: {
        Args: { p_request_id: string };
        Returns: undefined;
      };
      reopen_day: {
        Args: { p_close_date: string; p_location_id: string; p_reason: string };
        Returns: undefined;
      };
      replace_sales_lines: { Args: { p_batch: Json }; Returns: undefined };
      review_supplier_invoice: {
        Args: {
          p_invoice_id: string;
          p_review_note?: string;
          p_status: Database["public"]["Enums"]["invoice_status"];
        };
        Returns: undefined;
      };
      save_alert_settings: {
        Args: {
          p_stocktake_threshold_jod: number;
          p_waste_threshold_jod: number;
        };
        Returns: undefined;
      };
      save_stocktake_counts: {
        Args: { p_lines: Json; p_stocktake_id: string };
        Returns: undefined;
      };
      start_stocktake: { Args: { p_location_id: string }; Returns: string };
      submit_stocktake: {
        Args: { p_stocktake_id: string };
        Returns: undefined;
      };
      update_audit_visit: {
        Args: {
          p_notes?: string;
          p_scores?: Json;
          p_visit_date?: string;
          p_visit_id: string;
        };
        Returns: undefined;
      };
    };
    Enums: {
      hospitality_type: "vip" | "complaint" | "staff";
      invoice_status: "pending" | "approved" | "rejected";
      location_type: "warehouse" | "branch";
      movement_type:
        | "opening"
        | "purchase"
        | "production_in"
        | "production_out"
        | "transfer_in"
        | "transfer_out"
        | "sale_deduction"
        | "waste"
        | "hospitality"
        | "stocktake_adjustment"
        | "reversal";
      ownership_type: "company" | "franchise";
      product_type: "raw" | "processed" | "sellable";
      product_unit: "kg" | "pcs";
      sales_source: "foodics" | "talabat" | "careem" | "manual" | "pos";
      stocktake_status: "draft" | "submitted" | "approved";
      transfer_status: "pending" | "completed" | "cancelled";
      user_role:
        | "admin"
        | "branch_manager"
        | "warehouse_staff"
        | "accountant"
        | "inspector";
    };
    CompositeTypes: {
      [_ in never]: never;
    };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<
  keyof Database,
  "public"
>];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals;
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      hospitality_type: ["vip", "complaint", "staff"],
      invoice_status: ["pending", "approved", "rejected"],
      location_type: ["warehouse", "branch"],
      movement_type: [
        "opening",
        "purchase",
        "production_in",
        "production_out",
        "transfer_in",
        "transfer_out",
        "sale_deduction",
        "waste",
        "hospitality",
        "stocktake_adjustment",
        "reversal",
      ],
      ownership_type: ["company", "franchise"],
      product_type: ["raw", "processed", "sellable"],
      product_unit: ["kg", "pcs"],
      sales_source: ["foodics", "talabat", "careem", "manual", "pos"],
      stocktake_status: ["draft", "submitted", "approved"],
      transfer_status: ["pending", "completed", "cancelled"],
      user_role: [
        "admin",
        "branch_manager",
        "warehouse_staff",
        "accountant",
        "inspector",
      ],
    },
  },
} as const;
