#ifndef DBDIMP_H
#define DBDIMP_H
/*
   $Id: Ingres.sh,v 2.101 1997/09/12 06:26:47 ht000 Exp $

   Copyright (c) 1994,1995  Tim Bunce
   Copyright (c) 1996,1997  Henrik Tougaard (ht@datani.dk)
   				Ingres modifications
   
   You may distribute under the terms of either the GNU General Public
   License or the Artistic License, as specified in the Perl README file.

*/
#define NEED_DBIXS_VERSION 7

#include <DBIXS.h>              /* installed by the DBI module  */

EXEC SQL INCLUDE SQLDA;
EXEC SQL INCLUDE SQLCA;

typedef struct imp_fbh_st imp_fbh_t;

struct imp_drh_st {
    dbih_drc_t com;         /* MUST be first element in structure   */
};


/* Define dbh implementor data structure */
struct imp_dbh_st {
    dbih_dbc_t com;         /* MUST be first element in structure   */
    int        session;     /* session id for this connection */
};

/* Define sth implementor data structure */
struct imp_sth_st {
    dbih_stc_t com;         /* MUST be first element in structure   */

    IISQLDA    sqlda;       /* descriptor for statement (select) */
    char      *name;        /* statement name!!! */
    int        st_num;      /* statement number */
    int        done_desc;   /* have we described this sth yet ?	*/
    IISQLDA    ph_sqlda;    /* descriptor for placeholders */
    imp_fbh_t *fbh;	    /* array of imp_fbh_t structs	*/
};

struct imp_fbh_st { 	    /* field buffer EXPERIMENTAL */
    imp_sth_t *imp_sth;	    /* 'parent' statement */

    /* Ingres description of the field	*/
    IISQLVAR*   var;        /* pointer to Ingres description */
    int         nullable;   /* 1 if field is nullable */
    int         origtype;   /* the ingres type (as given by Ingres originally), this type has possibly been modified...*/
    char        type[2];    /* type "i"=int, "f"=double, "s"=string */
    int         len;        /* length of field in bytes */
    int         origlen;    /* length of the field in Ingres */

    /* Our storage space for the field data as it's fetched	*/
    short       indic;      /* null/trunc indicator variable	*/
    SV*         sv;         /* buffer for the data (perl & ingres) */
    union   {
        int *   iv;
        double* nv;
        char*   pv;
    } var_ptr;              /* buffer for data */
};


void    dbd_init _((dbistate_t *dbistate));
int	dbd_db_login _((SV *dbh, char* dbname, char* user, char* pass));
int	dbd_db_do _((SV *dbh, char *statement, char *attribs, SV *params));
int	dbd_db_rows _((SV *dbh, imp_dbh_t *imp_dbh));
int	dbd_db_commit _((SV *dbh));
int	dbd_db_rollback _((SV * dbh));
int	dbd_db_disconnect _((SV * dbh));
void	dbd_db_destroy _((SV * dbh));
int	dbd_db_STORE_attrib _((SV *dbh, SV *keysv, SV* valuesv));
SV*	dbd_db_FETCH_attrib _((SV *dbh, SV *keysv));
int	dbd_st_prepare _((SV * sth, char *statement, SV* attribs));
int     dbd_describe _((SV *h, imp_sth_t *imp_sth));
int     dbd_bind_ph  _((SV *sth, imp_sth_t *imp_sth,
                SV *param, SV *value, IV sql_type, SV *attribs,
				int is_inout, IV maxlen));
int	dbd_st_execute _((SV *sth));
AV*	dbd_st_fetch _((SV *sth));
int	dbd_st_rows _((SV *sth, imp_sth_t *imp_sth));
int	dbd_st_finish _((SV *sth));
void	dbd_st_destroy _((SV *sth));
int	dbd_st_STORE_attrib _((SV *dbh, SV *keysv, SV* valuesv));
SV*	dbd_st_FETCH_attrib _((SV *dbh, SV *keysv));
/* end */
#endif
