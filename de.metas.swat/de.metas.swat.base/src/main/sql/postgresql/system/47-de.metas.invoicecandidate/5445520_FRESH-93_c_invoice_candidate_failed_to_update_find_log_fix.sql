
DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_failed_to_update_v;


DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_missing_aggregation_group_v;
CREATE OR REPLACE VIEW de_metas_invoicecandidate.c_invoice_candidate_missing_aggregation_group_v AS 
SELECT ic.c_invoice_candidate_id, ic.created, ic.updated
FROM c_invoice_candidate ic
WHERE true 
	AND ic.c_invoice_candidate_headeraggregation_effective_id IS NULL 
	AND ic.processed = 'N'::bpchar 
	AND ic.istoclear = 'N'::bpchar 
	AND (ic.updated + '00:10:00'::interval) < now()
ORDER BY ic.updated DESC;

COMMENT ON VIEW de_metas_invoicecandidate.c_invoice_candidate_missing_aggregation_group_v
  IS 'ICs that don''t yet have an aggregation group, but were created/updated more than 10 minutes ago.
see issue FRESH-93';


DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_stale_qtyinvoiced_v;
CREATE OR REPLACE VIEW de_metas_invoicecandidate.c_invoice_candidate_stale_qtyinvoiced_v AS 
SELECT ic.c_invoice_candidate_id, ic.qtyinvoiced, sum(ila.qtyinvoiced) AS sum
FROM c_invoice_candidate ic
   JOIN c_invoice_line_alloc ila ON ic.c_invoice_candidate_id = ila.c_invoice_candidate_id
WHERE true 
	AND ic.processed = 'N' 
	AND (ic.updated + '00:10:00'::interval) < now()
GROUP BY ic.c_invoice_candidate_id, ic.qtyinvoiced
HAVING ic.qtyinvoiced <> sum(ila.qtyinvoiced);

COMMENT ON VIEW de_metas_invoicecandidate.c_invoice_candidate_stale_qtyinvoiced_v
  IS 'ICs that have an inconsistend QtyInvoiced value and were created/updated more than 10 minutes ago.
see issue FRESH-93';


DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_wrong_qtydelivered_iol_v;
CREATE OR REPLACE VIEW de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_iol_v AS 
SELECT 
	ic.c_invoice_candidate_id, 
	ic.created, 
	ic.updated, 
	dt.name, 
	COALESCE(ic.datetoinvoice_override, ic.datetoinvoice) AS "coalesce", 
	ic.qtydelivered, 
	sum(iol.movementqty) AS sum
FROM c_invoice_candidate ic
   JOIN c_doctype dt ON dt.c_doctype_id = ic.c_doctypeinvoice_id
   JOIN c_invoicecandidate_inoutline ic_iol ON ic_iol.c_invoice_candidate_id = ic.c_invoice_candidate_id
   JOIN m_inoutline iol ON iol.m_inoutline_id = ic_iol.m_inoutline_id
   JOIN m_inout io ON io.m_inout_id = iol.m_inout_id
   LEFT JOIN c_orderline ol ON ol.c_orderline_id = ic.c_orderline_id
   LEFT JOIN c_invoice_candidate_recompute icr ON icr.c_invoice_candidate_id = ic.c_invoice_candidate_id
WHERE true 
	AND (ic.updated + interval '10 minutes') < now() 
	AND COALESCE(ic.processed_override, ic.processed) = 'N'
	AND io.docstatus IN ('CO', 'CL')
	AND icr.c_invoice_candidate_id IS NULL 
	AND ol.c_orderline_id IS NULL 
GROUP BY 
	ic.c_invoice_candidate_id, 
	ic.created, 
	ic.updated, 
	dt.name, 
	COALESCE(ic.datetoinvoice_override, ic.datetoinvoice), 
	ic.qtydelivered
HAVING abs(ic.qtydelivered) <> abs(sum(iol.movementqty)) OR abs(ic.QtyOrdered) <> abs(sum(iol.MovementQty))
ORDER BY COALESCE(ic.datetoinvoice_override, ic.datetoinvoice);

COMMENT ON VIEW de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_iol_v
  IS 'ICs that 
* do reference an M_InOutLine and 
* do _not_ reference a C_OrderLine and
* have an inconsistent QtyDelivered or QtyOrdered value and
* were created/updated more than 10 minutes ago.
see Issue FRESH-93';


DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_wrong_qtydelivered_ol_v;
DROP VIEW IF EXISTS de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_ol_v;
CREATE OR REPLACE VIEW de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_ol_v AS 
SELECT ic.c_invoice_candidate_id, ic.created, ic.updated, ic.qtyordered, ol.qtyordered AS ol_qtyordered, ic.qtydelivered, ol.qtydelivered AS ol_qtydelivered
FROM c_invoice_candidate ic
   JOIN c_orderline ol ON ol.c_orderline_id = ic.c_orderline_id
   JOIN c_order o ON o.c_order_id = ol.c_order_id
   LEFT JOIN c_invoice_candidate_recompute icr ON icr.c_invoice_candidate_id = ic.c_invoice_candidate_id
WHERE true 
	AND (ic.updated + interval '10 minutes') < now() 
	AND COALESCE(ic.processed_override, ic.processed) = 'N' 
	AND icr.c_invoice_candidate_id IS NULL 
	AND o.docstatus IN ('CO', 'CL') 
	AND (ic.qtydelivered <> ol.qtydelivered OR ic.qtyordered <> ol.qtyordered);

COMMENT ON VIEW de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_ol_v
  IS 'ICs that 
* reference a C_OrderLine and
* have an inconsistend QtyDelivered or QtyOrdered value and
* were created/updated more than 10 minutes ago.
see Issue FRESH-93';


CREATE OR REPLACE VIEW de_metas_invoicecandidate.c_invoice_candidate_failed_to_update_v AS 
SELECT 
	now() AS found, 
	NULL::timestamp with time zone AS reenqueued, 
	'N'::character(1) AS iserroracknowledged, 
	'C_Invoice_Candidate_Wrong_Qty_iol_v'::text AS problem_found_by, 
	ic.ad_client_id, ic.ad_org_id, ic.c_invoice_candidate_id, ic.c_orderline_id, ic.created, ic.createdby, ic.isactive, ic.qtytoinvoice, ic.updated, ic.updatedby, ic.schedulerresult, ic.priceactual_override, ic.discount_override, ic.bill_bpartner_id, ic.bill_location_id, ic.bill_user_id, ic.invoicerule, ic.qtytoinvoicenetamt, ic.dateinvoiced, ic.istoclear, ic.m_product_id, ic.dateordered, ic.processed, ic.priceactual, ic.c_currency_id, ic.qtyordered, ic.qtydelivered, ic.qtyinvoiced, ic.qtytoinvoice_override, ic.qtytoinvoice_overridefulfilled, ic.c_charge_id, ic.bill_bpartner_override_id, ic.invoicerule_override, ic.m_pricingsystem_id, ic.discount, ic.netamttoinvoice, ic.netamtinvoiced, ic.c_invoice_candidate_agg_id, ic.lineaggregationkey, ic.lineaggregationkey_suffix, ic.c_ilcandhandler_id, ic.ad_table_id, ic.record_id, ic.iserror, ic.ad_note_id, ic.errormsg, ic.datetoinvoice, ic.datetoinvoice_override, ic.c_conversiontype_id, ic.invoicescheduleamtstatus, ic.ismanual, ic.description, ic.ad_user_incharge_id, ic.headeraggregationkey, ic.splitamt, ic.descriptionheader, ic.descriptionbottom, ic.priceentered, ic.priceentered_override, ic.issotrx, ic.allowconsolidateinvoice, ic.qualitydiscountpercent_effective, ic.qualitynote_receiptschedule, ic.qualitydiscountpercent, ic.qualitydiscountpercent_override, ic.isindispute, ic.qtywithissues, ic.qtyorderedoverunder, ic.reasondiscount, ic.c_uom_id, ic.price_uom_id, ic.c_order_id, ic.c_activity_id, ic.c_tax_id, ic.qtytoinvoiceinpriceuom, ic.isprinted, ic.line, ic.c_doctypeinvoice_id, ic.m_material_tracking_id, ic.approvalforinvoicing, ic.c_tax_override_id, ic.poreference, ic.dateacct, ic.deliverydate, ic.m_inout_id, ic.priceactual_net_effective, ic.istaxincluded, ic.qtyenteredtu, ic.qtytoinvoicebeforediscount, ic.istaxincluded_override, ic.c_invoice_candidate_headeraggregation_id, ic.c_invoice_candidate_headeraggregation_override_id, ic.headeraggregationkey_calc, ic.c_invoice_candidate_headeraggregation_effective_id, ic.headeraggregationkeybuilder_id, ic.first_ship_bplocation_id, ic.isinoutapprovedforinvoicing, ic.qtywithissues_effective, ic.processed_override, ic.processed_calc, ic.task_08848_fixed, ic.lineaggregationkeybuilder_id, ic.ispackagingmaterial, ic.isedirecipient, ic.isedienabled, ic.m_pricelist_version_id, ic.qualityinvoicelinegrouptype
FROM c_invoice_candidate ic
WHERE ic.c_invoice_candidate_id IN ( SELECT c_invoice_candidate_id FROM de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_iol_v)
UNION 
SELECT 
	now() AS found, 
	NULL::timestamp with time zone AS reenqueued, 
	'N'::bpchar AS iserroracknowledged, 
	'C_Invoice_Candidate_Wrong_Qty_ol_v'::text AS problem_found_by, 
	ic.ad_client_id, ic.ad_org_id, ic.c_invoice_candidate_id, ic.c_orderline_id, ic.created, ic.createdby, ic.isactive, ic.qtytoinvoice, ic.updated, ic.updatedby, ic.schedulerresult, ic.priceactual_override, ic.discount_override, ic.bill_bpartner_id, ic.bill_location_id, ic.bill_user_id, ic.invoicerule, ic.qtytoinvoicenetamt, ic.dateinvoiced, ic.istoclear, ic.m_product_id, ic.dateordered, ic.processed, ic.priceactual, ic.c_currency_id, ic.qtyordered, ic.qtydelivered, ic.qtyinvoiced, ic.qtytoinvoice_override, ic.qtytoinvoice_overridefulfilled, ic.c_charge_id, ic.bill_bpartner_override_id, ic.invoicerule_override, ic.m_pricingsystem_id, ic.discount, ic.netamttoinvoice, ic.netamtinvoiced, ic.c_invoice_candidate_agg_id, ic.lineaggregationkey, ic.lineaggregationkey_suffix, ic.c_ilcandhandler_id, ic.ad_table_id, ic.record_id, ic.iserror, ic.ad_note_id, ic.errormsg, ic.datetoinvoice, ic.datetoinvoice_override, ic.c_conversiontype_id, ic.invoicescheduleamtstatus, ic.ismanual, ic.description, ic.ad_user_incharge_id, ic.headeraggregationkey, ic.splitamt, ic.descriptionheader, ic.descriptionbottom, ic.priceentered, ic.priceentered_override, ic.issotrx, ic.allowconsolidateinvoice, ic.qualitydiscountpercent_effective, ic.qualitynote_receiptschedule, ic.qualitydiscountpercent, ic.qualitydiscountpercent_override, ic.isindispute, ic.qtywithissues, ic.qtyorderedoverunder, ic.reasondiscount, ic.c_uom_id, ic.price_uom_id, ic.c_order_id, ic.c_activity_id, ic.c_tax_id, ic.qtytoinvoiceinpriceuom, ic.isprinted, ic.line, ic.c_doctypeinvoice_id, ic.m_material_tracking_id, ic.approvalforinvoicing, ic.c_tax_override_id, ic.poreference, ic.dateacct, ic.deliverydate, ic.m_inout_id, ic.priceactual_net_effective, ic.istaxincluded, ic.qtyenteredtu, ic.qtytoinvoicebeforediscount, ic.istaxincluded_override, ic.c_invoice_candidate_headeraggregation_id, ic.c_invoice_candidate_headeraggregation_override_id, ic.headeraggregationkey_calc, ic.c_invoice_candidate_headeraggregation_effective_id, ic.headeraggregationkeybuilder_id, ic.first_ship_bplocation_id, ic.isinoutapprovedforinvoicing, ic.qtywithissues_effective, ic.processed_override, ic.processed_calc, ic.task_08848_fixed, ic.lineaggregationkeybuilder_id, ic.ispackagingmaterial, ic.isedirecipient, ic.isedienabled, ic.m_pricelist_version_id, ic.qualityinvoicelinegrouptype
FROM c_invoice_candidate ic
WHERE ic.c_invoice_candidate_id IN ( SELECT c_invoice_candidate_id FROM de_metas_invoicecandidate.c_invoice_candidate_wrong_qty_ol_v)
UNION 
SELECT 
	now() AS found, 
	NULL::timestamp with time zone AS reenqueued, 
	'N'::bpchar AS iserroracknowledged, 
	'C_Invoice_Candidate_Stale_QtyInvoiced_v'::text AS problem_found_by, 
	ic.ad_client_id, ic.ad_org_id, ic.c_invoice_candidate_id, ic.c_orderline_id, ic.created, ic.createdby, ic.isactive, ic.qtytoinvoice, ic.updated, ic.updatedby, ic.schedulerresult, ic.priceactual_override, ic.discount_override, ic.bill_bpartner_id, ic.bill_location_id, ic.bill_user_id, ic.invoicerule, ic.qtytoinvoicenetamt, ic.dateinvoiced, ic.istoclear, ic.m_product_id, ic.dateordered, ic.processed, ic.priceactual, ic.c_currency_id, ic.qtyordered, ic.qtydelivered, ic.qtyinvoiced, ic.qtytoinvoice_override, ic.qtytoinvoice_overridefulfilled, ic.c_charge_id, ic.bill_bpartner_override_id, ic.invoicerule_override, ic.m_pricingsystem_id, ic.discount, ic.netamttoinvoice, ic.netamtinvoiced, ic.c_invoice_candidate_agg_id, ic.lineaggregationkey, ic.lineaggregationkey_suffix, ic.c_ilcandhandler_id, ic.ad_table_id, ic.record_id, ic.iserror, ic.ad_note_id, ic.errormsg, ic.datetoinvoice, ic.datetoinvoice_override, ic.c_conversiontype_id, ic.invoicescheduleamtstatus, ic.ismanual, ic.description, ic.ad_user_incharge_id, ic.headeraggregationkey, ic.splitamt, ic.descriptionheader, ic.descriptionbottom, ic.priceentered, ic.priceentered_override, ic.issotrx, ic.allowconsolidateinvoice, ic.qualitydiscountpercent_effective, ic.qualitynote_receiptschedule, ic.qualitydiscountpercent, ic.qualitydiscountpercent_override, ic.isindispute, ic.qtywithissues, ic.qtyorderedoverunder, ic.reasondiscount, ic.c_uom_id, ic.price_uom_id, ic.c_order_id, ic.c_activity_id, ic.c_tax_id, ic.qtytoinvoiceinpriceuom, ic.isprinted, ic.line, ic.c_doctypeinvoice_id, ic.m_material_tracking_id, ic.approvalforinvoicing, ic.c_tax_override_id, ic.poreference, ic.dateacct, ic.deliverydate, ic.m_inout_id, ic.priceactual_net_effective, ic.istaxincluded, ic.qtyenteredtu, ic.qtytoinvoicebeforediscount, ic.istaxincluded_override, ic.c_invoice_candidate_headeraggregation_id, ic.c_invoice_candidate_headeraggregation_override_id, ic.headeraggregationkey_calc, ic.c_invoice_candidate_headeraggregation_effective_id, ic.headeraggregationkeybuilder_id, ic.first_ship_bplocation_id, ic.isinoutapprovedforinvoicing, ic.qtywithissues_effective, ic.processed_override, ic.processed_calc, ic.task_08848_fixed, ic.lineaggregationkeybuilder_id, ic.ispackagingmaterial, ic.isedirecipient, ic.isedienabled, ic.m_pricelist_version_id, ic.qualityinvoicelinegrouptype
FROM c_invoice_candidate ic
WHERE ic.c_invoice_candidate_id IN ( SELECT c_invoice_candidate_id FROM de_metas_invoicecandidate.c_invoice_candidate_stale_qtyinvoiced_v)
UNION 
SELECT 
	now() AS found, 
	NULL::timestamp with time zone AS reenqueued, 
	'N'::bpchar AS iserroracknowledged, 
	'C_Invoice_Candidate_Missing_Aggregation_Group_v'::text AS problem_found_by, 
	ic.ad_client_id, ic.ad_org_id, ic.c_invoice_candidate_id, ic.c_orderline_id, ic.created, ic.createdby, ic.isactive, ic.qtytoinvoice, ic.updated, ic.updatedby, ic.schedulerresult, ic.priceactual_override, ic.discount_override, ic.bill_bpartner_id, ic.bill_location_id, ic.bill_user_id, ic.invoicerule, ic.qtytoinvoicenetamt, ic.dateinvoiced, ic.istoclear, ic.m_product_id, ic.dateordered, ic.processed, ic.priceactual, ic.c_currency_id, ic.qtyordered, ic.qtydelivered, ic.qtyinvoiced, ic.qtytoinvoice_override, ic.qtytoinvoice_overridefulfilled, ic.c_charge_id, ic.bill_bpartner_override_id, ic.invoicerule_override, ic.m_pricingsystem_id, ic.discount, ic.netamttoinvoice, ic.netamtinvoiced, ic.c_invoice_candidate_agg_id, ic.lineaggregationkey, ic.lineaggregationkey_suffix, ic.c_ilcandhandler_id, ic.ad_table_id, ic.record_id, ic.iserror, ic.ad_note_id, ic.errormsg, ic.datetoinvoice, ic.datetoinvoice_override, ic.c_conversiontype_id, ic.invoicescheduleamtstatus, ic.ismanual, ic.description, ic.ad_user_incharge_id, ic.headeraggregationkey, ic.splitamt, ic.descriptionheader, ic.descriptionbottom, ic.priceentered, ic.priceentered_override, ic.issotrx, ic.allowconsolidateinvoice, ic.qualitydiscountpercent_effective, ic.qualitynote_receiptschedule, ic.qualitydiscountpercent, ic.qualitydiscountpercent_override, ic.isindispute, ic.qtywithissues, ic.qtyorderedoverunder, ic.reasondiscount, ic.c_uom_id, ic.price_uom_id, ic.c_order_id, ic.c_activity_id, ic.c_tax_id, ic.qtytoinvoiceinpriceuom, ic.isprinted, ic.line, ic.c_doctypeinvoice_id, ic.m_material_tracking_id, ic.approvalforinvoicing, ic.c_tax_override_id, ic.poreference, ic.dateacct, ic.deliverydate, ic.m_inout_id, ic.priceactual_net_effective, ic.istaxincluded, ic.qtyenteredtu, ic.qtytoinvoicebeforediscount, ic.istaxincluded_override, ic.c_invoice_candidate_headeraggregation_id, ic.c_invoice_candidate_headeraggregation_override_id, ic.headeraggregationkey_calc, ic.c_invoice_candidate_headeraggregation_effective_id, ic.headeraggregationkeybuilder_id, ic.first_ship_bplocation_id, ic.isinoutapprovedforinvoicing, ic.qtywithissues_effective, ic.processed_override, ic.processed_calc, ic.task_08848_fixed, ic.lineaggregationkeybuilder_id, ic.ispackagingmaterial, ic.isedirecipient, ic.isedienabled, ic.m_pricelist_version_id, ic.qualityinvoicelinegrouptype
FROM c_invoice_candidate ic
WHERE ic.c_invoice_candidate_id IN ( SELECT c_invoice_candidate_id FROM de_metas_invoicecandidate.c_invoice_candidate_missing_aggregation_group_v);

COMMENT ON VIEW de_metas_invoicecandidate.c_invoice_candidate_failed_to_update_v
  IS 'Union that selects all invoice candidates which were identified by one of the individual views.
Issue FRESH-93';

