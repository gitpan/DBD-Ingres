/*
   $Id: Ingres.xs,v 1.5 1997/01/15 08:14:19 ht Exp $

   Copyright (c) 1994,1995  Tim Bunce

   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file.

*/

#include "Ingres.h"

/* --- Variables --- */


DBISTATE_DECLARE;


MODULE = DBD::Ingres    PACKAGE = DBD::Ingres

BOOT:
    items = 0;  /* avoid 'unused variable' warning */
    DBISTATE_INIT;
    /* XXX this interface will change: */
    DBI_IMP_SIZE("DBD::Ingres::dr::imp_data_size", sizeof(imp_drh_t));
    DBI_IMP_SIZE("DBD::Ingres::db::imp_data_size", sizeof(imp_dbh_t));
    DBI_IMP_SIZE("DBD::Ingres::st::imp_data_size", sizeof(imp_sth_t));
    dbd_init(DBIS);


void
errstr(h)
    SV *        h
    CODE:
    /* called from DBI::var TIESCALAR code for $DBI::errstr     */
    D_imp_xxh(h);
    ST(0) = sv_mortalcopy(DBIc_ERRSTR(imp_xxh));

void
rows(h)
    SV *    h
    CODE:
    /* returns number of rows for last query, undef if error */
    int retval;
    retval = dbd_rows(h);
    if (retval < 0) {
        XST_mUNDEF(0);          /* error */
    } else if (retval == 0) {
        XST_mPV(0, "0E0");      /* true but zero */
    } else {
        XST_mIV(0, retval);     /* rowcount */
    }
    

MODULE = DBD::Ingres    PACKAGE = DBD::Ingres::dr

void
discon_all(drh)
    SV *       drh
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
    XST_mIV(0, 1);



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
    ST(0) = dbd_db_commit(dbh) ? &sv_yes : &sv_no;

void
rollback(dbh)
    SV *        dbh
    CODE:
    ST(0) = dbd_db_rollback(dbh) ? &sv_yes : &sv_no;


void
STORE(dbh, keysv, valuesv)
    SV *        dbh
    SV *        keysv
    SV *        valuesv
    CODE:
    ST(0) = &sv_yes;
    if (!dbd_db_STORE(dbh, keysv, valuesv))
        if (!DBIS->set_attr(dbh, keysv, valuesv))
            ST(0) = &sv_no;

void
FETCH_attrib_(dbh, keysv)
    SV *        dbh
    SV *        keysv
    ALIAS:
    FETCH = 1
    CODE:
    SV *valuesv = dbd_db_FETCH(dbh, keysv);
    if (!valuesv)
        valuesv = DBIS->get_attr(dbh, keysv);
    ST(0) = valuesv;    /* dbd_db_FETCH did sv_2mortal  */


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
DESTROY(dbh)
    SV *        dbh
    PPCODE:
    D_imp_dbh(dbh);
    ST(0) = &sv_yes;
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



MODULE = DBD::Ingres    PACKAGE = DBD::Ingres::st


void
_prepare(sth, statement, attribs=Nullsv)
    SV *        sth
    char *      statement
    SV *        attribs
    CODE:
    DBD_ATTRIBS_CHECK("_prepare", sth, attribs);
    ST(0) = dbd_st_prepare(sth, statement/*, attribs*/) ? &sv_yes : &sv_no;


void
execute(sth, ...)
    SV *        sth
    CODE:
    D_imp_sth(sth);
    int retval;
    retval = dbd_st_execute(sth);
    if (retval < 0)
        XST_mUNDEF(0);          /* error */
    else if (retval == 0)
        XST_mPV(0, "0E0");      /* true but zero */
    else
        XST_mIV(0, retval);     /* OK: rowcount */

void
fetch(sth)
    SV *        sth
    CODE:
    AV *av = dbd_st_fetchrow(sth);
    ST(0) = (av) ? sv_2mortal(newRV((SV *)av)) : &sv_undef;

void
fetchrow(sth)
    SV *        sth
    PPCODE:
    D_imp_sth(sth);
    AV *av;
    av = dbd_st_fetchrow(sth);
    if (av) {
        int num_fields = AvFILL(av)+1;
        int i;
        EXTEND(sp, num_fields);
        for(i=0; i < num_fields; ++i) {
            PUSHs(AvARRAY(av)[i]);
        }
    }

void
STORE(sth, keysv, valuesv)
    SV *        sth
    SV *        keysv
    SV *        valuesv
    CODE:
    ST(0) = &sv_yes;
    if (!dbd_st_STORE(sth, keysv, valuesv))
	if (!DBIS->set_attr(sth, keysv, valuesv))
	    ST(0) = &sv_no;


void
FETCH_attrib_(sth, keysv)
    SV *        sth
    SV *        keysv
    ALIAS:
    FETCH = 1
    CODE:
    SV *valuesv = dbd_st_FETCH(sth, keysv);
    if (!valuesv)
	valuesv = DBIS->get_attr(sth, keysv);
    ST(0) = valuesv;    /* dbd_st_FETCH did sv_2mortal  */


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
DESTROY(sth)
    SV *        sth
    PPCODE:
    D_imp_sth(sth);
    ST(0) = &sv_yes;
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
