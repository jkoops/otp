/*
 * %CopyrightBegin%
 * 
 * Copyright Ericsson AB 2001-2009. All Rights Reserved.
 * 
 * The contents of this file are subject to the Erlang Public License,
 * Version 1.1, (the "License"); you may not use this file except in
 * compliance with the License. You should have received a copy of the
 * Erlang Public License along with this software. If not, it can be
 * retrieved online at http://www.erlang.org/.
 * 
 * Software distributed under the License is distributed on an "AS IS"
 * basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See
 * the License for the specific language governing rights and limitations
 * under the License.
 * 
 * %CopyrightEnd%
 */
/* $Id$
 * hipe_bif1.h
 *
 * Performance analysis support.
 */
#ifndef HIPE_BIF1_H
#define HIPE_BIF1_H

struct hipe_call_count {
    unsigned count;
    Uint opcode;
};

extern unsigned int hipe_trap_count;

#endif /* HIPE_BIF1_H */