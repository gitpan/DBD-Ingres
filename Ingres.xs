/*
#   $Id: Ingres.xs,v 2.100 1997/09/10 08:00:41 ht000 Exp $
#
#   Copyright (c) 1994,1995,1996,1997  Tim Bunce
#   Modified for DBD::Ingres by Henrik Tougaard <ht@datani.dk>
#
#   You may distribute under the terms of either the GNU General Public
#   License or the Artistic License, as specified in the Perl README file.
*/

#include "Ingres.h"
DBISTATE_DECLARE;

MODULE = DBD::Ingres    PACKAGE = DBD::Ingres

REQUIRE:    1.929
PROTOTYPES: DISABLE

BOOT:
    items = 0;  /* avoid 'unused variable' warning */
    DBISTATE_INIT;
    /* XXX this interface will change: */
    DBI_IMP_SIZE("DBD::Ingres::dr::imp_data_size", sizeof(imp_drh_t));
    DBI_IMP_SIZE("DBD::Ingres::db::imp_data_size", sizeof(imp_dbh_t));
    DBI_IMP_SIZE("DBD::Ingres::st::imp_data_size", sizeof(imp_sth_t));
    dbd_init(DBIS);

MODULE = DBD::Ingres    PACKAGE = DBD::Ingres::dr

# disconnect_all renamed and ALIAS'd to avoid length clash on VMS :-}
void
discon_all_(drh)
    SV *        drh
    ALIAS:
        disconnect_all = 1
    CODE:
    if (!dirty && !SvTRUE(perl_get_sv("DBI::PERL_ENDING",0))) {
        D_imp_drh(drh);
        sv_setiv(DBIc_ERR(imp_drh), (IV)1);
        sv_setpv(DBIc_ERRSTR(imp_drh),
                (char*)"disconnect_all not implemented");
        DBIh_EVENT2(drh, ERROR_event,
                DBIc_ERR(imp_drh), DBIc_ERRSTR(imp_drh));
        XSRETURN(0);
    }
    /* perl_destruct with perl_destruct_level and $SIG{__WARN__} set	*/
    /* to a code ref core dumps when sv_2cv triggers warn loop.		*/
    if (perl_destruct_level)
	perl_destruct_level = 0;
    XST_mIV(0, 1);



# ------------------------------------------------------------
# database level interface
# ------------------------------------------------------------
MODULE = DBD::Ingres    PACKAGE = DBD::Ingres::db

void
_login(dbh, dbname, uid, pwd)
    SV *        dbh
    char *      dbname
    char *      uid
    char *      pwd
    CODE:
    ST(0) = dbd_db_login(dbh, dbname, uid, pwd) ? &sv_yes : &sv_no;

void
_do(dbh, statement, attribs="", params=Nullsv)
    SV *        dbh
    char *      statement
    char *      attribs
    SV *        params
    PREINIT:
    int		retval;
    CODE:
    retval = dbd_db_do(dbh, statement, attribs, params);
    if (retval < 0) {
        XST_mUNDEF(0);          /* error */
    } else if (retval == 0) {
        XST_mPV(0, "0E0");      /* true but zero */
    } else {
        XST_mIV(0, retval);     /* rowcount */
    }

void
commit(dbh)
    SV *        dbh
    CODE:
    D_imp_dbh(dbh);
    /* Check for commit() being called whilst refs to cursors	*/
    /* still exists. This needs some more thought.		*/
    if (DBIc_ACTIVE_KIDS(imp_dbh) && DBIc_WARN(imp_dbh) && !dirty) {
	warn("commit(%s) invalidates %d active cursor(s)",
	    SvPV(dbh,na), (int)DBIc_ACTIVE_KIDS(imp_dbh));
    }
    if (DBIc_has(imp_dbh,DBIcf_AutoCommit))
	    warn("commit ineffective with AutoCommit");
    ST(0) = dbd_db_commit(dbh) ? &sv_yes : &sv_no;

void
rollback(dbh)
    SV *       dbh
    CODE:
    D_imp_dbh(dbh);
    /* Check for rollback() being called whilst refs to cursors	*/
    /* still exists. This needs some more thought.		*/
    if (DBIc_ACTIVE_KIDS(imp_dbh) && DBIc_WARN(imp_dbh) && !dirty) {
	warn("rollback(%s) invalidates %d active cursor(s)",
	    SvPV(dbh,na), (int)DBIc_ACTIVE_KIDS(imp_dbh));
    }
    if (DBIc_has(imp_dbh,DBIcf_AutoCommit))
	    warn("rollback ineffective with AutoCommit");
    ST(0) = dbd_db_rollback(dbh) ? &sv_yes : &sv_no;

void
disconnect(dbh)
    SV *        dbh
    CODE:
    D_imp_dbh(dbh);
    if ( !DBIc_ACTIVE(imp_dbh) ) {
        XSRETURN_YES;
    }
    /* Check for disconnect() being called whilst refs to cursors       */
    /* still exists. This needs some more thought.                      */
    if (DBIc_ACTIVE_KIDS(imp_dbh) && DBIc_WARN(imp_dbh) && !dirty) {
	warn("disconnect(%s) invalidates %d active cursor(s)",
	    SvPV(dbh,na), (int)DBIc_ACTIVE_KIDS(imp_dbh));
    }
    ST(0) = dbd_db_disconnect(dbh) ? &sv_yes : &sv_no;


void
STORE(dbh, keysv, valuesv)
    SV *        dbh
    SV *        keysv
    SV *        valuesv
    CODE:
    ST(0) = &sv_yes;
    if (!dbd_db_STORE_attrib(dbh, keysv, valuesv))
        if (!DBIS->set_attr(dbh, keysv, valuesv))
            ST(0) = &sv_no;

void
FETCH(dbh, keysv)
    SV *        dbh
    SV *        keysv
    CODE:
    SV *valuesv = dbd_db_FETCH_attrib(dbh, keysv);
    if (!valuesv)
        valuesv = DBIS->get_attr(dbh, keysv);
    ST(0) = valuesv;    /* dbd_db_FETCH_attrib did sv_2mortal  */


void
DESTROY(dbh)
    SV *        dbh
    PPCODE:
    D_imp_dbh(dbh);
    ST(0) = &sv_yes;
    if (DBIc_IADESTROY(imp_dbh)) { /* want's ineffective destroy */
        DBIc_ACTIVE_off(imp_dbh);
    }
    if (!DBIc_IMPSET(imp_dbh)) {        /* was never fully set up       */
	if (DBIc_WARN(imp_dbh) && !dirty && dbis->debug >= 2)
	     warn("Database handle %s DESTROY ignored - never set up",
	        SvPV(dbh,na));
    }
    else {
        if (DBIc_ACTIVE(imp_dbh)) {
            if (DBIc_WARN(imp_dbh) && !dirty)
                warn("Database handle destroyed without explicit disconnect");
            dbd_db_disconnect(dbh);
        }
        dbd_db_destroy(dbh);
    }



# ------------------------------------------------------------
# statement interface
# ------------------------------------------------------------
MODULE = DBD::Ingres    PACKAGE = DBD::Ingres::st


void
_prepare(sth, statement, attribs=Nullsv)
    SV *        sth
    char *      statement
    SV *        attribs
    CODE:
    DBD_ATTRIBS_CHECK("_prepare", sth, attribs);
    ST(0) = dbd_st_prepare(sth, statement, attribs) ? &sv_yes : &sv_no;


void
rows(sth)
    SV *	sth
    CODE:
    D_imp_sth(sth);
    XST_mIV(0, dbd_st_rows(sth, imp_sth));


void
bind_param(sth, param, value, attribs=Nullsv)
    SV *	sth
    SV *	param
    SV *	value
    SV *	attribs
    CODE:
    {
    IV sql_type = 0;
    D_imp_sth(sth);
    if (attribs) {
	if (SvIOK(attribs)) {
	    sql_type = SvIV(attribs);
	    attribs = Nullsv;
	}
	else {
	    SV **svp;
	    DBD_ATTRIBS_CHECK("bind_param", sth, attribs);
	    if ((svp = hv_fetch((HV*)SvRV(attribs), "TYPE", 4, 0)) != NULL)
		sql_type = SvIV(*svp);
	}
    }
    ST(0) = dbd_bind_ph(sth, imp_sth, param, value, sql_type, attribs, FALSE, 0)
		? &sv_yes : &sv_no;
    }


void
bind_param_inout(sth, param, value_ref, maxlen, attribs=Nullsv)
    SV *	sth
    SV *	param
    SV *	value_ref
    IV 		maxlen
    SV *	attribs
    CODE:
    {
    IV sql_type = 0;
    D_imp_sth(sth);
    if (!SvROK(value_ref) || SvTYPE(SvRV(value_ref)) > SVt_PVMG)
	croak("bind_param_inout needs a reference to a scalar value");
    if (SvREADONLY(SvRV(value_ref)))
	croak(no_modify);
    if (attribs) {
	if (SvIOK(attribs)) {
	    sql_type = SvIV(attribs);
	    attribs = Nullsv;
	}
	else {
	    SV **svp;
	    DBD_ATTRIBS_CHECK("bind_param", sth, attribs);
	    if ((svp = hv_fetch((HV*)SvRV(attribs), "TYPE", 4, 0)) != NULL)
		sql_type = SvIV(*svp);
	}
    }
    ST(0) = dbd_bind_ph(sth, imp_sth, param, SvRV(value_ref), sql_type, attribs, TRUE, maxlen)
		? &sv_yes : &sv_no;
    }


void
execute(sth, ...)
    SV *        sth
    CODE:
    D_imp_sth(sth);
    int retval;
    if (items > 1) {
	/* Handle binding supplied values to placeholders	*/
	int i, error = 0;
        SV *idx;
	if (items-1 != DBIc_NUM_PARAMS(imp_sth)) {
	    croak("execute called with %ld bind variables, %d needed",
		    items-1, DBIc_NUM_PARAMS(imp_sth));
	    XSRETURN_UNDEF;
	}
        idx = sv_2mortal(newSViv(0));
	for(i=1; i < items ; ++i) {
	    sv_setiv(idx, i);
	    if (!dbd_bind_ph(sth, imp_sth, idx, ST(i), 0, Nullsv, FALSE, 0))
		++error;
	}
	if (error) {
	    XSRETURN_UNDEF;	/* dbd_bind_ph already registered error	*/
	}
    }
    retval = dbd_st_execute(sth);
    if (retval < 0)
        XST_mUNDEF(0);          /* error */
    else if (retval == 0)
        XST_mPV(0, "0E0");      /* true but zero */
    else
        XST_mIV(0, retval);     /* OK: rowcount */

void
fetchrow_arrayref(sth)
    SV *        sth
    ALIAS:
        fetch = 1
    CODE:
    AV *av = dbd_st_fetch(sth);
    ST(0) = (av) ? sv_2mortal(newRV((SV *)av)) : &sv_undef;

void
fetchrow_array(sth)
    SV *	sth
    ALIAS:
	fetchrow = 1
    PPCODE:
    D_imp_sth(sth);
    AV *av;
    av = dbd_st_fetch(sth);
    if (av) {
	int num_fields = AvFILL(av)+1;
	int i;
	EXTEND(sp, num_fields);
	for(i=0; i < num_fields; ++i) {
	    PUSHs(AvARRAY(av)[i]);
	}
    }

void
finish(sth)
    SV *        sth
    CODE:
    D_imp_sth(sth);
    D_imp_dbh_from_sth;
    if (!DBIc_ACTIVE(imp_dbh)) {
        /* Either an explicit disconnect() or global destruction        */
        /* has disconnected us from the database. Finish is meaningless */
        /* XXX warn */
        XSRETURN_YES;
    }
    if (!DBIc_ACTIVE(imp_sth)) {
        /* No active statement to finish        */
        XSRETURN_YES;
    }
    ST(0) = dbd_st_finish(sth) ? &sv_yes : &sv_no;

void
blob_read(sth, field, offset, len, destrv=Nullsv, destoffset=0)
    SV *        sth
    int field
    long        offset
    long        len
    SV *        destrv
    long        destoffset
    CODE:
    /* not implemented */
    ST(0) = &sv_undef;


void
STORE(sth, keysv, valuesv)
    SV *        sth
    SV *        keysv
    SV *        valuesv
    CODE:
    ST(0) = &sv_yes;
    if (!dbd_st_STORE_attrib(sth, keysv, valuesv))
	if (!DBIS->set_attr(sth, keysv, valuesv))
	    ST(0) = &sv_no;


void
FETCH_attrib_(sth, keysv)
    SV *        sth
    SV *        keysv
    ALIAS:
        FETCH = 1
    CODE:
    SV *valuesv = dbd_st_FETCH_attrib(sth, keysv);
    if (!valuesv)
	valuesv = DBIS->get_attr(sth, keysv);
    ST(0) = valuesv;    /* dbd_st_FETCH did sv_2mortal  */


void
DESTROY(sth)
    SV *        sth
    PPCODE:
    D_imp_sth(sth);
    ST(0) = &sv_yes;
    if (DBIc_IADESTROY(imp_sth)) { /* want's ineffective destroy */
        DBIc_ACTIVE_off(imp_sth);
    }
    if (!DBIc_IMPSET(imp_sth)) {        /* was never fully set up       */
	if (DBIc_WARN(imp_sth) && !dirty && dbis->debug >= 2)
	     warn("Statement handle %s DESTROY ignored - never set up",
		SvPV(sth,na));
    }
    else {
        if (DBIc_ACTIVE(imp_sth))
            dbd_st_finish(sth);
        dbd_st_destroy(sth);
    }



# end of Ingres.xs
