# Copyright 1999-2015 Gentoo Foundation
# Distributed under the terms of the GNU General Public License v2

EAPI=7

inherit cmake git-r3

DESCRIPTION="Finite element programs, libraries, and visualization tools - math C library"
HOMEPAGE="https://www.csc.fi/web/elmer"
EGIT_REPO_URI="https://github.com/ElmerCSC/elmerfem.git"

LICENSE="GPL-2 LGPL-2.1"
SLOT="0"

RDEPEND="
	sys-libs/ncurses:0=
	sys-libs/readline:0="
DEPEND="${RDEPEND}"

S="${WORKDIR}/${P}/${PN}"
