/*                               -*- Mode: C -*- 
 * $Id: //depot/tilpasninger/dbd-ingres/dbdimp.psc#6 $
 *
 * Copyright (c) 1994,1995  Tim Bunce
 *           (c) 1996,1997  Henrik Tougaard
 *
 * You may distribute under the terms of either the GNU General Public
 * License or the Artistic License, as specified in the Perl README file.
 *
 * This file is a copy of the oracle dbdimp.c, that has been mangled, cut
 * to shreds, thrown together and shamelessly mistreated, so that it can
 * have some (small) chance of success in the Ingres world.
 *
 * The blame for this abuse of Tim Bunce's good code lies solely on
 * me: htoug@cpan.org
 *
 */


EXEC SQL INCLUDE 'Ingres.sh';

DBISTATE_DECLARE;
static int cur_session;    /* the 'current' Ingres session_id */
static int nxt_session;    /* the next 'available' session_id */

static void dump_sqlda(sqlda)
    IISQLDA* sqlda;
{
    int i;
    if (dbis->debug < 3) return;
    PerlIO_printf(DBILOGFP, "Dump of sqlda:\n");
    PerlIO_printf(DBILOGFP, "  id: %c%c%c%c%c%c%c%c\n",
        sqlda->sqldaid[0], sqlda->sqldaid[1], sqlda->sqldaid[2],
        sqlda->sqldaid[3], sqlda->sqldaid[4], sqlda->sqldaid[5],
        sqlda->sqldaid[6], sqlda->sqldaid[7]);
    PerlIO_printf(DBILOGFP, "  bc: %d\n  sqln: %d, sqld: %d\n",
        sqlda->sqldabc, sqlda->sqln, sqlda->sqld);
    for (i=0; i<sqlda->sqld; ++i) {
        IISQLVAR* var = &sqlda->sqlvar[i];
        PerlIO_printf(DBILOGFP, "  sqlvar[%d]: type: %d, len: %d, ind: %d",
            i, var->sqltype, var->sqllen, var->sqlind);
        switch (var->sqltype) {
        case IISQ_INT_TYPE:
            PerlIO_printf(DBILOGFP, ", var: %d\n",
                *((int*)(var->sqldata)));
            break;
        case IISQ_FLT_TYPE:
            PerlIO_printf(DBILOGFP, ", var: %g\n",
                *((double*)(var->sqldata)));
            break;
        case IISQ_CHA_TYPE:
            PerlIO_printf(DBILOGFP, ", var: '%s'\n",
                var->sqldata);
            break;
        default:
            PerlIO_printf(DBILOGFP, ", unknown type: %d\n",
                var->sqltype);
        }
    }
}

static int
sql_check(h)
    SV * h;
{
    EXEC SQL BEGIN DECLARE SECTION;
    char errbuf[256];
    EXEC SQL END DECLARE SECTION;
    D_imp_xxh(h);
    SV *errstr = DBIc_ERRSTR(imp_xxh);

    if (sqlca.sqlcode < 0) { 
        if (dbis->debug >= 3) 
            PerlIO_printf(DBILOGFP, "DBD::Ingres:sql_check: sqlcode=%d",
                    sqlca.sqlcode);
        sv_setiv(DBIc_ERR(imp_xxh), (IV)sqlca.sqlcode);
        if (dbis->debug >= 3) 
            PerlIO_printf(DBILOGFP, " get errtext");
        EXEC SQL INQUIRE_INGRES(:errbuf = ERRORTEXT);
        { /* remove trailing "\n" */
            int i = strlen(errbuf)-1;
            while ((errbuf[i] == '\n' || errbuf[i] == ' ') && i > 1) {
                errbuf[i] = 0;
                --i;
            }
        }
        if (dbis->debug >= 3) 
            PerlIO_printf(DBILOGFP, " got errtext: '%s'", errbuf);
        sv_setpv(errstr, (char*)errbuf);
        if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, ", returning\n");
	DBIh_EVENT2(h, ERROR_event, DBIc_ERR(imp_xxh), errstr);
        return 0;
    } else return 1;
}

static void
error(h, error_num, text, state)
    SV * h;
    int error_num;
    char * text;
    char * state;
{
    D_imp_xxh(h);
    SV *errstr = DBIc_ERRSTR(imp_xxh);
    sv_setiv(DBIc_ERR(imp_xxh), (IV)error_num);
    sv_setpv(errstr, text);
    if (state != 0) sv_setpv(DBIc_STATE(imp_xxh), state);
    DBIh_EVENT2(h, ERROR_event, DBIc_ERR(imp_xxh), errstr);
}

static void
set_session(dbh)
    SV * dbh;
{
    D_imp_dbh(dbh);
    EXEC SQL BEGIN DECLARE SECTION;
    int session_id = imp_dbh->session;
    EXEC SQL END DECLARE SECTION;
    if (cur_session != session_id) {
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP, "set session_db(%d)\n", session_id);
        EXEC SQL SET_SQL(SESSION = :session_id);
        cur_session = session_id;
    }
}

void
dbd_init(dbistate)
    dbistate_t *dbistate;
{
    DBIS = dbistate;
    cur_session = 1;
    nxt_session = 1;
}

int
dbd_discon_all(drh, imp_drh)
    SV *drh;
    imp_drh_t *imp_drh;
{
    dTHR;

    /* Taken directly from DBD::Oracle:dbdimp.c Version 0.47 */
    /* The disconnect_all concept is flawed and needs more work */
    if (!dirty && !SvTRUE(perl_get_sv("DBI::PERL_ENDING",0))) {
        sv_setiv(DBIc_ERR(imp_drh), (IV)1);
        sv_setpv(DBIc_ERRSTR(imp_drh),
            (char*)"disconnect_all not implemented");
        DBIh_EVENT2(drh, ERROR_event,
            DBIc_ERR(imp_drh), DBIc_ERRSTR(imp_drh));
        return FALSE;
    }
    if (perl_destruct_level)
        perl_destruct_level = 0;
    return FALSE;
}

static U32* statement_numbers;    /* bitmask of reserved statement nos */
static int statement_max;         /* max bit number allocated (8 pr char) */

static void
release_statement(num)
    int num;
{
    if (num < 0 || num >= statement_max*8) return;
    statement_numbers[num/8] &= ~(1<<(num%8));
    if (dbis->debug >= 4)
        PerlIO_printf(DBILOGFP, "rel_st.nam: %d [%d]=%u\n", num, num/8,
                statement_numbers[num/8]);
}

static void
generate_statement_name(st_num, name)
    int * st_num;
    char * name;
{
    /* find a (new) statement -name for this statement.
    ** Names can be reused when the statement handle is destroyed.
    ** The number of active statements is limited by the PSF in Ingres
    */    
    int i, found=0, num;
    if (dbis->debug >= 4)
        PerlIO_printf(DBILOGFP, "gen_st.nam");
    for (i=0; i<statement_max; i++) {
        /* see if there is a free statement-name
           in the already allocated lump */
        int bit;
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, " [%d]=%u", i, statement_numbers[i]);
        for (bit=0; bit < 32; bit++) {
            if (((statement_numbers[i]>>bit) & 1) == 0) {
                /* free bit found */
                num = i*32+bit;
                found = 1;
                break;
            }
        }
        if (found) break;
    }
    if (!found) {
        /* allocate a new lump af numbers and take the first one */
        if (statement_max == 0) {
            /* first time round */
            if (dbis->debug >= 4)
                PerlIO_printf(DBILOGFP, " alloc first time");
            num = 0;
            Newz(42, statement_numbers, 8, U32);
            for(i = statement_max; i < statement_max+8; i++)
                statement_numbers[i] = 0;
            statement_max = 8;
        } else {
            num = statement_max * 32;
            if (dbis->debug >= 4)
                PerlIO_printf(DBILOGFP, " alloc to %d", statement_max);
            Renew(statement_numbers, statement_max+8, U32);
            for(i = statement_max; i < statement_max+8; i++)
                statement_numbers[i] = 0;
            statement_max += 8;
        }
    }
    statement_numbers[num/8] |= (1<<(num%8));
    sprintf(name, "s%d", num);
    if (dbis->debug >= 4)
        PerlIO_printf(DBILOGFP, " returns %d\n", num);
    *st_num = num;
}


static void
fbh_dump(fbh, i)
    imp_fbh_t *fbh;
    int i;
{
    PerlIO_printf(DBILOGFP, "fbh_dump:");
    PerlIO_printf(DBILOGFP, "fbh %d: '%s' %s, ",
            i, fbh->var->sqlname.sqlnamec,
            (fbh->nullable) ? "NULLable" : "");
    PerlIO_printf(DBILOGFP, "type %d,  origlen %d, len %d\n",
            fbh->origtype, fbh->origlen, fbh->len);
    PerlIO_printf(DBILOGFP, "       VAR: type: %d, len: %d, ind: %p\n",
            fbh->var->sqltype, fbh->var->sqllen, fbh->var->sqlind);
}

/* ================================================================== */

int
dbd_db_login(dbh, imp_dbh, dbname, user, pass)
    SV *dbh;
    imp_dbh_t *imp_dbh;
    EXEC SQL BEGIN DECLARE SECTION;
    char *dbname;
    char *user;
    char *pass;
    EXEC SQL END DECLARE SECTION;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int session;
    char * opt;
    EXEC SQL END DECLARE SECTION;
    dTHR;

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_login: dbname: %s\n", dbname);

    session = imp_dbh->session = nxt_session++;
    imp_dbh->trans_no = 1;
    
    opt = dbname;
    /* look for options in dbname. Syntax: dbname;options */
    while (*opt && *opt != ';') ++opt;
    if (*opt == ';') {
        *opt = 0; /* terminate dbname */
        ++opt;    /* point to options */
    }
    
    if (user && *user && *user != '/') {
        /* we have a username */
        if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, "    user='%s', opt='%s'\n",
                                user, opt);
        if (pass && *pass) {
/*OI*       EXEC SQL CONNECT :dbname SESSION :session
                 IDENTIFIED BY :user DBMS_PASSWORD=:pass OPTIONS=:opt;
/**/
/*64*
            warn("DBD::Ingres::connect non-OpenIngres: ignoring DBMS_PASSWORD");
            EXEC SQL CONNECT :dbname SESSION :session
                 IDENTIFIED BY :user OPTIONS=:opt;
/**/
        } else {
            EXEC SQL CONNECT :dbname SESSION :session
                 IDENTIFIED BY :user OPTIONS=:opt;
        }
    } else {
        /* just the databasename */
        if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, "    nouser\n");
        EXEC SQL CONNECT :dbname SESSION :session OPTIONS = :opt;
    }
    if (dbis->debug >= 3)
        PerlIO_printf(DBILOGFP, "    After connect, sqlcode=%d, session=%d\n",
                            sqlca.sqlcode, imp_dbh->session);
    cur_session = imp_dbh->session;
    if (!sql_check(dbh)) return 0;
    DBIc_IMPSET_on(imp_dbh);    /* imp_dbh set up now                   */
    DBIc_ACTIVE_on(imp_dbh);    /* call disconnect before freeing       */
    {
      /* get default autocommit state, so DBI knows about it */
        EXEC SQL BEGIN DECLARE SECTION;
        int autocommit_state;
        EXEC SQL END DECLARE SECTION;
        
        EXEC SQL SELECT INT4(DBMSINFO('AUTOCOMMIT_STATE'))
            INTO :autocommit_state;
        if (!sql_check(dbh)) return 0;

        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_connect(AUTOCOMMIT=%d)\n",
                    autocommit_state);
        DBIc_set(imp_dbh, DBIcf_AutoCommit, autocommit_state);
        if (!autocommit_state) {
            EXEC SQL COMMIT;
            if (!sql_check(dbh)) return 0;
        }
    }
    return 1;
}

int
dbd_db_do(dbh, statement)
    SV * dbh;
    EXEC SQL BEGIN DECLARE SECTION;
    char * statement;
    EXEC SQL END DECLARE SECTION;
{
    D_imp_dbh(dbh);
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_do(\"%s\")\n", statement);
    set_session(dbh);
    
    EXEC SQL EXECUTE IMMEDIATE :statement;
    if (!sql_check(dbh)) return -1;
    else return sqlca.sqlerrd[2]; /* rowcount */
}

int
dbd_db_commit(dbh, imp_dbh)
    SV* dbh;
    imp_dbh_t* imp_dbh;
{
    dTHR;
     
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_commit\n");

    /* Check for commit() being called whilst refs to cursors */
    /* still exists. This needs some more thought.            */
    if (DBIc_ACTIVE_KIDS(imp_dbh) && DBIc_WARN(imp_dbh) && !dirty) {
        warn("DBD::Ingres::commit(%s) invalidates %d active cursor(s)",
            SvPV(dbh,na), (int)DBIc_ACTIVE_KIDS(imp_dbh));
    }

    set_session(dbh);
    ++ imp_dbh->trans_no;
    EXEC SQL COMMIT;
    return sql_check(dbh);
}

int
dbd_db_rollback(dbh, imp_dbh)
    SV* dbh;
    imp_dbh_t* imp_dbh;
{
    dTHR;
     
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_rollback\n");

    /* Check for commit() being called whilst refs to cursors   */
    /* still exists. This needs some more thought.              */
    if (DBIc_ACTIVE_KIDS(imp_dbh) && DBIc_WARN(imp_dbh) && !dirty) {
        warn("DBD::Ingres::rollback(%s) invalidates %d active cursor(s)",
            SvPV(dbh,na), (int)DBIc_ACTIVE_KIDS(imp_dbh));
    }


    set_session(dbh);
    ++ imp_dbh->trans_no;
    EXEC SQL ROLLBACK;
    return sql_check(dbh);
}

SV*
dbd_db_get_dbevent(dbh, imp_dbh, wait)
    SV* dbh;
    imp_dbh_t* imp_dbh;
    SV* wait;
{
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_get_dbevent\n");

    set_session(dbh);
    if (!wait || !SvOK(wait) || !SvIOK(wait)) {
      EXEC SQL GET DBEVENT WITH WAIT;
    } else {
      EXEC SQL BEGIN DECLARE SECTION;
      int seconds;
      EXEC SQL END DECLARE SECTION;

      seconds = (int)SvIV(wait);
      EXEC SQL GET DBEVENT WITH WAIT = :seconds;
    }
    if (!sql_check(dbh)) return (&sv_undef);
{
    HV *result;
    EXEC SQL BEGIN DECLARE SECTION;
    char event_name    [80];
    char event_database[80];
    char event_owner   [80];
    char event_text    [256];
    char event_time    [26];
    EXEC SQL END DECLARE SECTION;

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "dbd_db_inquire_event\n");
    set_session(dbh);
    EXEC SQL INQUIRE_INGRES
      (:event_name     = DBEVENTNAME,
       :event_database = DBEVENTDATABASE,
       :event_text     = DBEVENTTEXT,
       :event_owner    = DBEVENTOWNER,
       :event_time     = DBEVENTTIME
       );
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "eventname = %s\n", event_name);
    if (!sql_check(dbh)) return (&sv_undef);
    if (!*event_name)    return (&sv_undef);
    result = newHV();

    hv_store(result, "name",     sizeof("name")    -1,
        newSVpv(event_name,    0),0);
    hv_store(result, "database", sizeof("database")-1,
        newSVpv(event_database,0),0);
    hv_store(result, "text",     sizeof("text")    -1,
        newSVpv(event_text,    0),0);
    hv_store(result, "owner",    sizeof("owner")   -1,
        newSVpv(event_owner,   0),0);
    hv_store(result, "time",     sizeof("time")    -1,
        newSVpv(event_time,    0),0);
    return(sv_2mortal(newRV_noinc((SV*)result)));
}
}

int
dbd_db_disconnect(dbh, imp_dbh)
    SV* dbh;
    imp_dbh_t* imp_dbh;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int transaction_active;
    EXEC SQL END DECLARE SECTION;
    dTHR;

    DBIc_ACTIVE_off(imp_dbh);
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_disconnect\n");

    set_session(dbh);
    EXEC SQL INQUIRE_INGRES(:transaction_active = TRANSACTION);
    if (transaction_active == 1){
        warn("DBD::Ingres: You should commit or rollback before disconnect.");
        warn("DBD::Ingres: Any outstanding changes have been rolledback.");
        EXEC SQL ROLLBACK;
        if (sqlca.sqlcode != 0) {
            warn("DBD::Ingres: problem rolling back");
        }
    }
    EXEC SQL DISCONNECT;
    /* We assume that disconnect will always work       */
    /* since most errors imply already disconnected.    */

    /* We don't free imp_dbh since a reference still exists */
    /* The DESTROY method is
     the only one to 'free' memory.     */
    return sql_check(dbh);
}

void
dbd_db_destroy(dbh, imp_dbh)
    SV* dbh;
    imp_dbh_t* imp_dbh;
{
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_destroy\n");

    if (DBIc_ACTIVE(imp_dbh))
        dbd_db_disconnect(dbh, imp_dbh);
    /* XXX free contents of imp_dbh */
    DBIc_IMPSET_off(imp_dbh);
}

int
dbd_db_STORE_attrib(dbh, imp_dbh, keysv, valuesv)
    SV *dbh;
    imp_dbh_t* imp_dbh;
    SV *keysv;
    SV *valuesv;
{
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on = SvTRUE(valuesv);

    set_session(dbh);
    if (kl==10 && strEQ(key, "AutoCommit")){
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_db_STORE(AUTOCOMMIT=");
        if (on) {
            EXEC SQL COMMIT;
            EXEC SQL SET AUTOCOMMIT ON;
            if (dbis->debug >= 3)
                PerlIO_printf(DBILOGFP,"ON), sqlcode=%d\n", sqlca.sqlcode);
        } else {
            EXEC SQL COMMIT;
            EXEC SQL SET AUTOCOMMIT OFF;
            if (dbis->debug >= 3)
                PerlIO_printf(DBILOGFP,"OFF), sqlcode=%d\n", sqlca.sqlcode);
        }
        DBIc_set(imp_dbh, DBIcf_AutoCommit, on);
    } else {
        return FALSE;
    }
    if (cachesv) /* cache value for later DBI 'quick' fetch? */
        hv_store((HV*)SvRV(dbh), key, kl, cachesv, 0);
    return TRUE;
}

SV *
dbd_db_FETCH_attrib(dbh, imp_dbh, keysv)
    SV* dbh;
    imp_dbh_t* imp_dbh;
    SV* keysv;
{
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    int i;
    SV *retsv = NULL;
    /* Default to caching results for DBI dispatch quick_FETCH  */
    int cacheit = TRUE;

    set_session(dbh);
    if (kl==10 && strEQ(key, "AutoCommit")){
        EXEC SQL BEGIN DECLARE SECTION;
        int autocommit_state;
        EXEC SQL END DECLARE SECTION;
        
        EXEC SQL SELECT INT4(DBMSINFO('AUTOCOMMIT_STATE'))
            INTO :autocommit_state;
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP,
                "DBD::Ingres::dbd_db_FETCH(AUTOCOMMIT=%d)sqlca=%d\n",
                autocommit_state, sqlca.sqlcode);
        DBIc_set(imp_dbh, DBIcf_AutoCommit, autocommit_state);
        retsv = newSVsv(boolSV(autocommit_state));
        cacheit = FALSE;   /* Don't cache AutoCommit state - some
                           /* fool^H^H^H^Huser may change it via SQL */
    }

    if (!retsv)
        return Nullsv;

    if (cacheit) { /* cache for next time (via DBI quick_FETCH) */
        hv_store((HV*)SvRV(dbh), key, kl, retsv, 0);
    }
    return (retsv);
}

/* === DBD_ST ======================================================= */

int hash(char *s) {
    int h = 0;
    while (*s) {
        h += (unsigned char)(*s);
        s++;
    }
    return h;
}

int
dbd_st_prepare(sth, imp_sth, statement, attribs)
    SV* sth;
    imp_sth_t* imp_sth;
    EXEC SQL BEGIN DECLARE SECTION;
    char *statement;
    EXEC SQL END DECLARE SECTION;
    SV* attribs;   /* unused */
{
    IISQLDA* sqlda;
    EXEC SQL BEGIN DECLARE SECTION;
    char name[32];
    EXEC SQL END DECLARE SECTION;
    D_imp_dbh_from_sth;

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_prepare('%s')\n", statement);

    imp_sth->done_desc = 0;
    sqlda = &imp_sth->sqlda;
    strcpy(sqlda->sqldaid, "SQLDA   ");
    sqlda->sqldabc = sizeof(IISQLDA);
    sqlda->sqln = IISQ_MAX_COLS;
    { /* Make a statement name - contains unique number +
         first part of statement (after select, as this is always a
         select statement */
        char *p = statement;
        char *n;
        while (*p && *p != 's' && *p != 'S') ++p; /* find s in select */
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Statement = %s \n", p);
        p += 6; /* points past select */
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Statement = %s \n", p);
        while (*p && *p <= 32) ++p; /* past any whitespace */
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Statement3 = %s \n", p);
        generate_statement_name(&imp_sth->st_num, name);
        /*imp_sth->st_num = hash(statement);
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Num = %d \n", imp_sth->st_num);
        sprintf(name, "s%d", imp_sth->st_num);*/
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Name = %s \n", name);
        n = name + strlen(name); /* points at \0 at end */
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Name1 = %s \n", n);
        *n++ = '_';
        if (dbis->debug >= 4)
            PerlIO_printf(DBILOGFP, "Name2 = %s \n", n);
        while (*p && n < (name+23)) {
            if (isalnum(*p)) {
                *n++ = *p;
            }
            ++p;
        }
        *n = 0;
        imp_sth->name = savepv(name);
    }
    if (dbis->debug >= 3)
        PerlIO_printf(DBILOGFP,
            "DBD::Ingres::dbd_st_prepare stmt('%s') name:%s, sqlda: %p\n",
            statement, name, sqlda);

    set_session(DBIc_PARENT_H(imp_sth));
    EXEC SQL PREPARE :name INTO sqlda FROM :statement;
    if (!sql_check(sth)) return 0;

    if (sqlda->sqld > sqlda->sqln) {
        /* too many cols returned - unlikely */
        croak("DBD::Ingres: Statement returns %d columns, max allowed is %d\n",
                sqlda->sqld, sqlda->sqln);
    }
    DBIc_NUM_FIELDS(imp_sth) = sqlda->sqld;

    /* See if there are any placeholders in the statement */
    {
        char *src = statement;
        int in_literal = 0;
        int in_string = 0;
        int in_comment = 0;
        while(*src) {
            if (*src == '"' && !in_string && !in_comment)
                in_literal = ~in_literal;
            else if (*src == '\'' && !in_literal && !in_comment)
                in_string = ~in_string;
            else if (*src == '/' && src[1] == '*' &&
                    !in_literal && !in_string)
                in_comment = 1;
            else if (in_comment && *src == '*' && src[1] == '/')
                in_comment = 0;
            if ((*src == '?') && !in_literal && !in_string && !in_comment)
                ++DBIc_NUM_PARAMS(imp_sth);
            ++src;
        }
    }
    if (DBIc_NUM_PARAMS(imp_sth) > 0) {
        IISQLDA *sqlda = &imp_sth->ph_sqlda;
        strcpy(sqlda->sqldaid, "SQLDA   ");
        sqlda->sqldabc = sizeof(IISQLDA);
        sqlda->sqln = IISQ_MAX_COLS;
        {
          /* initialize memory structures for bind variables. This is
             used in bind() to decide if memory was allocated already */

          int param_max = DBIc_NUM_PARAMS(imp_sth);
          int param_no;
          IISQLVAR* var;
          
          for (param_no=0; param_no < param_max; param_no++) {
            var = &imp_sth->ph_sqlda.sqlvar[param_no];
            var->sqldata = (char *) &sv_undef;
            var->sqllen  = 0;
          }
        }
    }

    if (dbis->debug >= 2)
        printf("DBD::Ingres::dbd_st_prepare: fields: %d, phs: %d\n",
                DBIc_NUM_FIELDS(imp_sth), DBIc_NUM_PARAMS(imp_sth));

    imp_sth->trans_no = imp_dbh->trans_no;
    DBIc_IMPSET_on(imp_sth);
    return 1;
}

int
dbd_describe(sth, imp_sth)
     SV *sth;
     imp_sth_t *imp_sth;
{
    IISQLDA* sqlda = &imp_sth->sqlda;
    int i;
    
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,
            "DBD::Ingres::dbd_describe(name: %s)\n", imp_sth->name);

    if (imp_sth->done_desc) {
      if (dbis->debug >= 3) 
          PerlIO_printf(DBILOGFP,
            "In: DBD::Ingres::dbd_describe() done_desc = true\n");
      return 1; /* success, already done it */
    }
    imp_sth->done_desc = 1;

    /* describe the statement and allocate bufferspace */
    Newz(42, imp_sth->fbh, DBIc_NUM_FIELDS(imp_sth) + 1, imp_fbh_t);
    for (i = 0; i < sqlda->sqld; i++)
    {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var = &sqlda->sqlvar[i];
        fbh->nullable = var->sqltype < 0;
        fbh->origtype = var->sqltype = abs(var->sqltype);
        fbh->origlen = var->sqllen;
        var->sqlname.sqlnamec[var->sqlname.sqlnamel] = 0;
        
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP, "  field %d, type=%d\n", 1, var->sqltype);
            
        switch (var->sqltype) {
        case IISQ_INT_TYPE:
            fbh->len = var->sqllen = sizeof(int);
            strcpy(fbh->type, "d");
            Newz(42, fbh->var_ptr.iv, 1, int);
            var->sqldata = (char*)fbh->var_ptr.iv;
            fbh->sv = NULL;
            break;
        case IISQ_MNY_TYPE: /* money - treat as float8 */
        case IISQ_DEC_TYPE: /* decimal */
        case IISQ_FLT_TYPE:
            fbh->len = var->sqllen = sizeof(double);
            var->sqltype = IISQ_FLT_TYPE;
            strcpy(fbh->type, "f");
            Newz(42, fbh->var_ptr.nv, 1, double);
            var->sqldata = (char*)fbh->var_ptr.nv;
            fbh->sv = NULL;
            break;
        case IISQ_DTE_TYPE:
            var->sqllen = IISQ_DTE_LEN;
            /* FALLTHROUGH */
        case IISQ_CHA_TYPE:
        case IISQ_VCH_TYPE:
        case IISQ_TXT_TYPE:
            var->sqltype = IISQ_CHA_TYPE;
            strcpy(fbh->type, "s");
            /* set up bufferspace */
            fbh->len = var->sqllen+1;
            fbh->sv = newSV((STRLEN)fbh->len);
            (void)SvUPGRADE(fbh->sv, SVt_PV);
            SvREADONLY_on(fbh->sv);
            (void)SvPOK_only(fbh->sv);
            var->sqldata = (char*)SvPVX(fbh->sv);
            fbh->var_ptr.pv = var->sqldata;
            break;
        default:        /* oh dear! */
            croak("DBD::Ingres: field %d has unsupported type %d\n",
                  i+1, var->sqltype);
            break;
        }

        if (fbh->nullable) {
            var->sqlind = &fbh->indic;
            var->sqltype = - var->sqltype;
                    /* changed sign indicates nullable */
        } else {
            var->sqlind = (short *)0;   /* no indicator variable*/
            fbh->indic = 0;
                 /* so that we can use this as an indicator variable later */
        }
        if (dbis->debug >= 2) {
            PerlIO_printf(DBILOGFP, "dumping it\n");
            fbh_dump(fbh, i);
        }
    } /* end allocation of field-data */

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_describe(%s) finished\n",
                imp_sth->name);

    return 1;
}


int
dbd_bind_ph (sth, imp_sth, param, value, sql_type, attribs, is_inout, maxlen)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *param;
    SV *value;
    IV sql_type;
    SV *attribs;
    int is_inout;
    IV maxlen;
{
    int param_no;
    int type = 0;  /* 1: int, 2: float, 3: string */
    IISQLVAR* var;
    int* buf;
    
    if (SvNIOK(param) ) {   /* passed as a number   */
        param_no = (int)SvIV(param);
    } else {
        croak("DBD::Ingres::bind_param: parameter not a number");
    }

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "DBD::Ingres::dbd_bind_ph(%d)\n",
            param_no);

    if (param_no < 1 || param_no > DBIc_NUM_PARAMS(imp_sth))
        croak("DBD::Ingres(bind_param): parameter outside range 1..%d",
            DBIc_NUM_PARAMS(imp_sth));

    if (imp_sth->ph_sqlda.sqld < param_no)
        imp_sth->ph_sqlda.sqld = param_no;

    var = &imp_sth->ph_sqlda.sqlvar[param_no-1];
    buf = ((int *) var->sqldata)-1;
    if (sql_type) {
        switch (sql_type) {
        case SQL_INTEGER:
        case SQL_SMALLINT:
            type = 1; break;
        case SQL_FLOAT:
        case SQL_REAL:
        case SQL_DOUBLE:
        case SQL_NUMERIC:
        case SQL_DECIMAL:
            type = 2; break;
        case SQL_CHAR:
        case SQL_VARCHAR:
            type = 3; break;
	default:
	    croak("DBD::Ingres::bind_param: Unknown TYPE: %d, param_no %d",
		sql_type, param_no);
        }
    } else if (!SvOK(value)) { /* NULL */
        croak(
           "Ingres(bind_param): sorry NULLs not allowed unless TYPE defined");
    } else if (SvIOK(value)) { /* integer */
        type = 1;
    } else if (SvNOK(value)) { /* float */
        type = 2;
    } else { /* char */
        type = 3;
    }
    if (dbis->debug >= 3)
        PerlIO_printf(DBILOGFP, "  type=%d\n", type);
    switch (type) {
      /* Poor mans memory management: We store the actual length of
         the buffer one int below var->sqldata. */
    case 1: {/* int */
        if (var->sqldata == (char *)&sv_undef) {
            Newz(42, buf, 2, int);
            *buf = 2;
            var->sqldata = (char*) (buf+1);
        } else if (*buf < 2) {
            Renew(buf, 2, int);
            *buf = 2;
            var->sqldata = (char*) (buf+1);
        }
        buf[1]       = (int)SvIV(value);
        var->sqlind  = 0;
        var->sqllen  = 4;
        var->sqltype = IISQ_INT_TYPE;
        break; }
    case 2: {/* float */
        int    need_int = (sizeof(double) + sizeof(int)-1)/sizeof(int) +1;
        double ptr;

        if (var->sqldata == (char *)&sv_undef) {
            Newz(42, buf, need_int, int);
            *buf = need_int;
            var->sqldata = (char*) (buf+1);
        } else if (*buf < need_int) {
            Renew(buf, need_int, int);
            *buf = need_int;
            var->sqldata = (char*) (buf+1);
        }
        ptr = (double)SvNV(value);
        /* Double probably not aligned properly: may cause alignment
           error in Ingres library? Hmm: works for Open Ingres 1.2 and
           Ingres 6.4. Should we spend 8 bytes for the length tag? */
        Move(&ptr, buf+1, 1, double); 
        var->sqlind  = 0;
        var->sqllen = 8;
        var->sqltype = IISQ_FLT_TYPE;
        break; }
    case 3: {/* string */
        STRLEN strlen;
        char   *string  = SvPV(value,strlen);
        int    need_int = ((strlen+1)*sizeof(char) + sizeof(int)-1) /
                                      sizeof(int) + 1;
        
        if (var->sqldata == (char *)&sv_undef) { /* initital allocation */
            Newz(42, buf, need_int, int);
            *buf = need_int;
            var->sqldata = (char *) (buf+1);
        } else {
            buf = ((int *) var->sqldata)-1; 
            if (*buf < need_int) { /* need to reallocate? */
                Renew(buf, need_int, int);
                *buf = need_int;
                var->sqldata = (char *) (buf+1);
            }
        }
        Move(string, var->sqldata, strlen+1, char);
        var->sqlind  = 0;
        var->sqllen  = strlen;
        var->sqltype = IISQ_CHA_TYPE;
        break; }
    }
    if (!SvOK(value)) {
        if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, "bind(NULL)");
        if (var->sqldata == (char *)&sv_undef) {
          Newz(42, buf, 2, int);
          *buf = 2;
          var->sqldata = (char*) (buf+1);
        } else if (*buf < 2) {
          Renew(buf, 2, int);
          *buf = 2;
          var->sqldata = (char*) (buf+1);
        }
        var->sqlind = (short*)var->sqldata; /* cheat a little - use
                                            ** var->sqldata as indicator
                                            ** variable as well - the
                                            ** actual value is never
                                            ** used!*/
        *var->sqlind = -1;
        var->sqltype = -var->sqltype;
    }
    if (dbis->debug >= 3) dump_sqlda(&imp_sth->ph_sqlda);
    return 1;
}

int
dbd_st_execute(sth, imp_sth)
/* >=0: OK, no of rows affected,
**  -1: OK, unknown number of rows affected,
**  -2: error */
    SV *sth;
    imp_sth_t *imp_sth;
{
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;
    dTHR;
    D_imp_dbh_from_sth;
 
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "DBD::Ingres::dbd_st_execute(%s)\n", imp_sth->name);

    /* needs to check for re-prepare (after commit etc.) */
    if (imp_sth->trans_no != imp_dbh->trans_no) {
        croak("DBD::Ingres: Attempt to execute a statement after commit");
    }

    if (!imp_sth->done_desc) {
        /* describe and allocate storage for results */
        if (!dbd_describe(sth, imp_sth))
            return -2; /* dbd_describe already called sql_check() */
    }

    /* Trigger execution of the statement */
    set_session(DBIc_PARENT_H(imp_sth));

    if (DBIc_NUM_FIELDS(imp_sth) == 0) {
        /* non-select statement: just execute it */
        if (dbis->debug >= 2)
            PerlIO_printf(DBILOGFP,
                "DBD::Ingres::dbd_st_execute - non-select, param=%d\n",
                imp_sth->ph_sqlda.sqld);

        if (imp_sth->ph_sqlda.sqld > 0) {
            EXEC SQL EXECUTE :name USING DESCRIPTOR &imp_sth->ph_sqlda;
        } else {
            EXEC SQL EXECUTE :name;
        }
        return sql_check(sth) ? sqlca.sqlerrd[2] : -2;
    } else {
	int is_readonly;
        /* select statement: open a cursor */
        EXEC SQL DECLARE :name CURSOR FOR :name;
	/* 0.23 open readonly unless an "FOR UPDATE"- clause is found in */
	/* select statement. This is done in Ingres.pm in prepare, and */
	/* is stored in the private variable $sth->{ing_readonly}. */
	{
	  SV** svp;
	  if ( (svp = hv_fetch((HV*)SvRV(sth), "ing_readonly", 12, 0)) != NULL
	      && SvTRUE(*svp)) is_readonly = 1;
	  else is_readonly = 0;
	}
        if (dbis->debug >= 2)
            PerlIO_printf(DBILOGFP,
                "DBD::Ingres::dbd_st_execute - cursor %s - param=%d %sreadonly\n",
                name, imp_sth->ph_sqlda.sqld, is_readonly ? "" : "NOT ");

        if (is_readonly) {
		if (imp_sth->ph_sqlda.sqld > 0) {
		    EXEC SQL OPEN :name FOR READONLY
			 USING DESCRIPTOR &imp_sth->ph_sqlda;
		} else {
		    EXEC SQL OPEN :name FOR READONLY;
		}
	} else {
		if (imp_sth->ph_sqlda.sqld > 0) {
		    EXEC SQL OPEN :name
			 USING DESCRIPTOR &imp_sth->ph_sqlda;
		} else {
		    EXEC SQL OPEN :name;
		}
	}
        if (!sql_check(sth)) return -2;
        DBIc_ACTIVE_on(imp_sth);
        return -1 /* Unknown number of rows */;
    }
}

AV *
dbd_st_fetch(sth, imp_sth)
    SV *     sth;
    imp_sth_t *imp_sth;
{
    IISQLDA* sqlda;
    int num_fields;
    int i;
    AV *av;
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;
    D_imp_dbh_from_sth;

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_fetch(%s)\n", imp_sth->name);

    /* needs to check for re-prepare (after commit etc.) */
    if (imp_sth->trans_no != imp_dbh->trans_no) {
        croak("DBD::Ingres: Attempt to fetch from statement after commit");
    }

    if (!DBIc_ACTIVE(imp_sth)) {
        error(sth, -7, "fetch without open cursor", 0);
        return Nullav;
    }
    set_session(DBIc_PARENT_H(imp_sth));
    sqlda = &imp_sth->sqlda;
    EXEC SQL FETCH :name USING DESCRIPTOR :sqlda;
    if (sqlca.sqlcode == 100) {
        dbd_st_finish(sth, imp_sth);
        return Nullav;
    } else
    if (!sql_check(sth)) return Nullav;

    /* Something was fetched, put the fields into the array */
    av = DBIS->get_fbav(imp_sth);
    num_fields = AvFILL(av)+1;

    if (dbis->debug >= 3)
        PerlIO_printf(DBILOGFP, "    dbd_st_fetch %d fields\n", num_fields);

    for(i=0; i < num_fields; ++i) {
        imp_fbh_t *fbh = &imp_sth->fbh[i];
        IISQLVAR *var = fbh->var;
        int ch;
        SV *sv = AvARRAY(av)[i]; /* Note: we (re)use the SV in the AV */
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP, "    Field #%d: ", i);
        if (fbh->indic == -1) {
            /* NULL value */
            (void)SvOK_off(sv);
            if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, "NULL\n");
        } else {
            switch (fbh->type[0]) {
            case 'd':
                sv_setiv(sv, (IV)*(int*)var->sqldata);
                if (dbis->debug >= 3)
                    PerlIO_printf(DBILOGFP, "Int: %ld %d %d\n",
                          SvIV(sv), fbh->var_ptr.iv, *(int*)var->sqldata);
                break;
            case 'f':
                sv_setnv(sv, *(double*)var->sqldata);
                if (dbis->debug >= 3)
                    PerlIO_printf(DBILOGFP, "Double: %lf\n", SvNV(sv));
                break;
            case 's':
                SvCUR(fbh->sv) = fbh->len;
                SvPVX(fbh->sv)[fbh->len-1] = 0;
                /* strip trailing blanks */
                if ((fbh->origtype == IISQ_DTE_TYPE ||
                     fbh->origtype == IISQ_CHA_TYPE ||
                     fbh->origtype == IISQ_TXT_TYPE)
                 && DBIc_has(imp_sth, DBIcf_ChopBlanks)) {
                    for (ch = fbh->len - 2;
                         SvPVX(fbh->sv)[ch] == ' ';
                         --ch)
                             SvPVX(fbh->sv)[ch] = 0;
                }
                sv_setsv(sv, fbh->sv);
                SvCUR(sv) = strlen(SvPVX(sv));
                if (dbis->debug >= 3)
                    PerlIO_printf(DBILOGFP, "Text: '%s', Chop: %d\n",
                        SvPVX(sv), DBIc_has(imp_sth, DBIcf_ChopBlanks));
                break;
            default:
                croak("DBD::Ingres: wierd field-type '%s' in field no. %d?\n",
                            fbh->type, i);
            }
        }
    }
    if (dbis->debug >= 3) PerlIO_printf(DBILOGFP, "    End fetch\n");
    return av;
}

int
dbd_st_rows(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    EXEC SQL BEGIN DECLARE SECTION;
    int rowcount;
    EXEC SQL END DECLARE SECTION;
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "dbd_rows\n");
    set_session(DBIc_PARENT_H(imp_sth));
    EXEC SQL INQUIRE_INGRES(:rowcount = ROWCOUNT);
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP, "rowcount = %d\n", rowcount);
    if (!sql_check(sth)) return -1;
    else return rowcount;
}

int
dbd_st_finish(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    EXEC SQL BEGIN DECLARE SECTION;
    char* name = imp_sth->name;
    EXEC SQL END DECLARE SECTION;
    dTHR;
    
    /* Cancel further fetches from this cursor.                 */
    if (DBIc_ACTIVE(imp_sth)) {
        if (dbis->debug >= 3)
            PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s)\n",
                imp_sth->name);
        set_session(DBIc_PARENT_H(imp_sth));
        EXEC SQL CLOSE :name;
    }
    DBIc_ACTIVE_off(imp_sth);

    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_finish(%s)\n", imp_sth->name);

    return 1;
}

void
dbd_st_destroy(sth, imp_sth)
    SV *sth;
    imp_sth_t *imp_sth;
{
    int i;
    D_imp_dbh_from_sth;
    
    if (dbis->debug >= 2)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_destroy(%s)\n",
            imp_sth->name);

    release_statement(imp_sth->st_num);

    /* XXX free contents of imp_sth here */

    DBIc_IMPSET_off(imp_sth);
}

int
dbd_st_blob_read(sth, imp_sth,
                 field, offset, len, destrv, destoffset)
    SV *sth;
    imp_sth_t *imp_sth;
    int field;
    long offset;
    long len;
    SV *destrv;
    long destoffset;
{
   die("DBD::Ingres: blob_read not (yet) implemented - sorry!");
   return 0;
}

int
dbd_st_STORE_attrib(sth, imp_sth, keysv, valuesv)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *keysv;
    SV *valuesv;
{
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    SV *cachesv = NULL;
    int on = SvTRUE(valuesv);
    dTHR;

    if (dbis->debug >=3)
        PerlIO_printf(DBILOGFP,"DBD::Ingres::dbd_st_STORE(%s)->{%s}\n",
                imp_sth->name, key);

    return FALSE; /* no values to store */
    
    if (cachesv) /* cache value for later DBI 'quick' fetch? */
        hv_store((HV*)SvRV(sth), key, kl, cachesv, 0);
    return TRUE;
}


SV *
dbd_st_FETCH_attrib(sth, imp_sth, keysv)
    SV *sth;
    imp_sth_t *imp_sth;
    SV *keysv;
{
    STRLEN kl;
    char *key = SvPV(keysv,kl);
    int i;
    SV *retsv = NULL;
    /* Default to caching results for DBI dispatch quick_FETCH  */
    int cacheit = TRUE;

    if (dbis->debug >= 3)
        PerlIO_printf(DBILOGFP, "DBD::Ingres::dbd_st_FETCH(%s)->{%s}\n",
                imp_sth->name, key);

    if (!imp_sth->done_desc && !dbd_describe(sth, imp_sth)) {
        /* dbd_describe called sql_check()                      */
        /* we can't return Nullsv here because the xs code will */
        /* then just pass the attribute name to DBI for FETCH.  */
        croak("DBD::Ingres: Describe failed during %s->FETCH(%s)",
            SvPV(sth, na), key);
    }

    if (kl==10 && strEQ(key, "CursorName")) {
        return newSVpv(imp_sth->name, 0);
    }

    i = DBIc_NUM_FIELDS(imp_sth);

    if (kl==4 && strEQ(key, "TYPE")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0) {
            int type;
            switch (imp_sth->fbh[i].origtype) {
            case IISQ_INT_TYPE:
                type = SQL_INTEGER;
                /* Note should probably be others based on length */
                break;
            case IISQ_MNY_TYPE:
            case IISQ_DEC_TYPE: /* decimal */
                type = SQL_DECIMAL;
                break;
            case IISQ_FLT_TYPE:
                type = SQL_DOUBLE;
                break;
            case IISQ_DTE_TYPE:
                type = SQL_DATE;
                break;
            case IISQ_CHA_TYPE:
            case IISQ_TXT_TYPE:
                type = SQL_CHAR;
                break;
            case IISQ_VCH_TYPE:
                type = SQL_VARCHAR;
                break;
            default:        /* oh dear! */
                type = 0;
                break;
            }
            av_store(av, i, newSViv(type));
        }
    } else if (kl==8 && strEQ(key, "NULLABLE")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, (imp_sth->fbh[i].nullable) ? &sv_yes : &sv_no);
    } else if (kl==4 && strEQ(key, "NAME")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].var->sqlname.sqlnamec,
                        imp_sth->fbh[i].var->sqlname.sqlnamel));
    } else if (kl==9 && strEQ(key, "PRECISION")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0) {
            int len;
            switch (imp_sth->fbh[i].origtype) {
            case IISQ_INT_TYPE:
                switch (imp_sth->fbh[i].origlen) {
                case 1:
                    len = 3; /* 0..255 */;
                    break;
                case 2:
                    len = 5; /* 0 .. 65000 */
                    break;
                case 4:
                default:
                    len = 10; /* 0 .. 2_140_000_000 */
                    break;
                }
                break;
            case IISQ_MNY_TYPE:
                len = 32; /* Ingres constant! */
                break;
            case IISQ_DEC_TYPE: /* decimal */
                len = imp_sth->fbh[i].origlen;
                break;
            case IISQ_FLT_TYPE:
                len = 15; /* approx digits in double */
                break;
            case IISQ_DTE_TYPE:
                len = 24; /* size of a date */
                break;
            case IISQ_CHA_TYPE:
            case IISQ_TXT_TYPE:
            case IISQ_VCH_TYPE:
                len = imp_sth->fbh[i].origlen;
                break;
            default:        /* oh dear! */
                break;
            }
            if (len > 0)
                av_store(av, i, newSViv((IV)len));
            else
                av_store(av, i, Nullsv);
        }
    } else if (kl==5 && strEQ(key, "SCALE")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, Nullsv);
    } else if (kl==8 && strEQ(key, "ing_type") ||
               kl==9 && strEQ(key, "ing_types")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSVpv(imp_sth->fbh[i].type, 0));
    } else if (kl==11 && strEQ(key, "ing_lengths") ||
               kl==6 && strEQ(key, "SqlLen")){
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origlen));
    } else if ((kl==12 && strEQ(key, "ing_ingtypes")) ||
               (kl==7 && strEQ(key, "SqlType")) ) {
        AV *av = newAV();
        retsv = newRV_noinc((SV*)av);
        while(--i >= 0)
            av_store(av, i, newSViv((IV)imp_sth->fbh[i].origtype));
    } else {
        return Nullsv;
    }
    if (cacheit) { /* cache for next time (via DBI quick_FETCH) */
        SV **svp = hv_fetch((HV*)SvRV(sth), key, kl, 1);
        sv_free(*svp);
        *svp = retsv; 

        /*hv_store((HV*)SvRV(sth), key, kl, retsv, 0); */
        (void)SvREFCNT_inc(retsv);      /* so sv_2mortal won't free it  */
    }
    return sv_2mortal(retsv);
}

