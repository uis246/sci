# Copyright 1999-2022 Gentoo Authors
# Distributed under the terms of the GNU General Public License v2

EAPI=8

PYTHON_COMPAT=( python3_{8..10} )

# OCP uses "python-single-r1" only because VTK uses "python-single-r1".
inherit check-reqs cmake llvm multiprocessing python-single-r1 toolchain-funcs

MY_PN=OCP
MY_PV="${PV//_/-}"
MY_P="${MY_PN}-${MY_PV}"
OCCT_PV=$(ver_cut 1-3)

DESCRIPTION="Python wrapper for OCCT generated using pywrap"
HOMEPAGE="https://github.com/CadQuery/OCP"
SRC_URI="https://github.com/CadQuery/OCP/archive/refs/tags/${MY_PV}.tar.gz -> ${P}.tar.gz"

LICENSE="Apache-2.0"
KEYWORDS="~amd64 ~x86"
SLOT="0"
REQUIRED_USE="${PYTHON_REQUIRED_USE}"

# CMake and VTK requirements derive from the "OCP/CMakeLists.txt" file
# generated by the src_prepare() phase. OCP currently requires opencascade
# (OCCT) to be built with "-DUSE_GLES2=OFF" and thus "-gles2". See also:
#     https://github.com/CadQuery/OCP/issues/46#issuecomment-808920994
BDEPEND="
	>=dev-libs/lief-0.11.5[python,${PYTHON_SINGLE_USEDEP}]
	>=dev-util/cmake-3.16
"
RDEPEND="
	${PYTHON_DEPS}
	sci-libs/opencascade:0/7.5[json,tbb,vtk]
	>=sci-libs/vtk-9.0.0[python,${PYTHON_SINGLE_USEDEP}]
"
DEPEND="${RDEPEND}
	$(python_gen_cond_dep '
		>=dev-python/cadquery-pywrap-'${OCCT_PV}'_rc0[${PYTHON_USEDEP}]')
"

S="${WORKDIR}/${MY_P}"

# The source "OCP/CMakeLists.txt" file is output by "bindgen" in src_prepare().
CMAKE_IN_SOURCE_BUILD=True

# Ensure the path returned by get_llvm_prefix() contains clang.
llvm_check_deps() {
	has_version -r "sys-devel/clang:${LLVM_SLOT}"
}

cadquery-ocp_check_reqs() {
	CHECKREQS_DISK_BUILD=1300M check-reqs_pkg_${EBUILD_PHASE}
}

pkg_pretend() {
	cadquery-ocp_check_reqs
}

pkg_setup() {
	cadquery-ocp_check_reqs
	llvm_pkg_setup
	python-single-r1_pkg_setup
}

# OCP currently requires manual configuration, compilation, and installation
# loosely inspired by the conda-specific "build-bindings-job.yml" file.
#
# Note that the cmake_src_prepare() function called below handles user patches.
src_prepare() {
	# Most recently installed version of Clang.
	local _CLANG_VERSION="$(CPP=clang clang-fullversion)"

	# Most recently installed version (excluding trailing patch) of VTK.
	local _VTK_VERSION="$(best_version -r sci-libs/vtk)"
	_VTK_VERSION="$(ver_cut 1-2 "${_VTK_VERSION##sci-libs/vtk}")"

	# Absolute dirname of the most recently installed Clang include directory,
	# mimicing similar logic in the "dev-python/shiboken2" ebuild. See also:
	#     https://bugs.gentoo.org/619490
	local _CLANG_INCLUDE_DIR="${EPREFIX}/usr/lib/clang/${_CLANG_VERSION}/include"

	# Absolute filename of the most recently installed Clang shared library.
	local _CLANG_LIB_FILE="$(get_llvm_prefix)/lib64/libclang.so"

	# Absolute dirname of OCCT's include and shared library directories.
	local _OCCT_INCLUDE_DIR="${EPREFIX}/usr/include/opencascade"
	local _OCCT_LIB_DIR="${EPREFIX}/usr/lib64/opencascade"

	# Absolute dirname of a temporary directory to store symbol tables for this
	# OCCT version dumped below by the "dump_symbols.py" script.
	local _OCCT_DUMP_SYMBOLS_ROOT_DIR="${T}/dump_symbols"
	local _OCCT_DUMP_SYMBOLS_DIR="${_OCCT_DUMP_SYMBOLS_ROOT_DIR}/lib_linux"

	# Absolute dirname of VTK's include directory,
	local _VTK_INCLUDE_DIR="${EPREFIX}/usr/include/vtk-${_VTK_VERSION}"

	# Ensure the above paths exist as a crude sanity test.
	test -d "${_CLANG_INCLUDE_DIR}" || die "${_CLANG_INCLUDE_DIR} not found."
	test -f "${_CLANG_LIB_FILE}"    || die "${_CLANG_LIB_FILE} not found."
	test -d "${_OCCT_INCLUDE_DIR}"  || die "${_OCCT_INCLUDE_DIR} not found."
	test -d "${_OCCT_LIB_DIR}"      || die "${_OCCT_LIB_DIR} not found."
	test -d "${_VTK_INCLUDE_DIR}"   || die "${_VTK_INCLUDE_DIR} not found."

	# "dev-python/clang-python" atom targeting this Clang version.
	local _CLANG_PYTHON_ATOM="dev-python/clang-python-${_CLANG_VERSION}"

	# Ensure "dev-python/clang-python" targets this Clang version.
	has_version -r "=${_CLANG_PYTHON_ATOM}" ||
		die "${_CLANG_PYTHON_ATOM} not installed."

	# Remove all vendored paths.
	rm -r conda opencascade pywrap *.dat || die

	# Inject a symlink to OCCT's include directory.
	ln -s "${_OCCT_INCLUDE_DIR}" opencascade || die

	# Inject a symlink from OCCT's shared library directory into this temporary
	# directory as required by the "dump_symbols.py" script.
	mkdir -p "${_OCCT_DUMP_SYMBOLS_DIR}" || die
	ln -s "${_OCCT_LIB_DIR}" "${_OCCT_DUMP_SYMBOLS_DIR}"/. || die

	# Update all hardcoded OCCT shared library versions in "dump_symbols.py".
	sed -i -e 's~\(\.so\.\)[0-9]\+.[0-9]\+.[0-9]\+~\1'${OCCT_PV}'~' \
		dump_symbols.py || die

	# Dump (i.e., generate) symbol tables for this OCCT version.
	einfo 'Dumping OCCT symbol tables...'
	${EPYTHON} dump_symbols.py "${_OCCT_DUMP_SYMBOLS_ROOT_DIR}" || die

	# Generate OCCT bindings in the "OCP/" subdirectory.
	einfo 'Building OCP CMake binary tree...'
	${EPYTHON} -m bindgen \
		--verbose \
		--njobs $(makeopts_jobs) \
		--libclang "${_CLANG_LIB_FILE}" \
		--include "${_CLANG_INCLUDE_DIR}" \
		--include "${_VTK_INCLUDE_DIR}" \
		all ocp.toml || die

	# Remove the source "FindOpenCascade.cmake" after generating bindings,
	# which copied that file to the target "OCP/FindOpenCascade.cmake".
	rm FindOpenCascade.cmake || die

	#FIXME: Submit an issue recommending upstream replace their
	#non-working "OCP/FindOpenCascade.cmake" file with a standard top-level
	#"CMakeLists.txt" file that finds dependency paths: e.g., via @waebbl
	#    find_package(vtk 9 CONFIG REQUIRED)
	#    if(TARGET VTK::VTK)
	#      get_target_property(VTK_INCLUDE_DIRS VTK::VTK INTERFACE_INCLUDE_DIRECTORIES)
	#    endif()

	# Replace all hardcoded paths in "OCP/FindOpenCascade.cmake" with
	# standard OCCT paths derived above. That file is both fundamentally
	# broken and useless, as the ${CASROOT} environment variable and
	# "/usr/lib64/cmake/opencascade-${PV}/OpenCASCADEConfig.cmake" file
	# already reliably identify all requisite OpenCASCADE paths. Failure to
	# patch this file results in src_configure() failures resembling:
	#     -- Could NOT find OPENCASCADE (missing: OPENCASCADE_LIBRARIES)
	sed -i \
		-e 's~$ENV{CONDA_PREFIX}/include/opencascade\b~'${_OCCT_INCLUDE_DIR}'~' \
		-e 's~$ENV{CONDA_PREFIX}/lib\b~'${_OCCT_LIB_DIR}'~' \
		-e 's~$ENV{CONDA_PREFIX}/Library/\(lib\|include/opencascade\)~~' \
		OCP/FindOpenCascade.cmake || die

	# Patch the "OCP/CMakeLists.txt" file generated by "bindgen" above, passed
	# as an absolute path both here and below to minimize eclass issues.
	CMAKE_USE_DIR="${S}/OCP" cmake_src_prepare
}

src_configure() {
	local mycmakeargs=(
		-B "${S}/OCP.build"
		-DPYTHON_EXECUTABLE="${PYTHON}"
		-Wno-dev
	)

	CMAKE_USE_DIR="${S}/OCP" cmake_src_configure
}

src_compile() {
	CMAKE_USE_DIR="${S}/OCP.build" cmake_src_compile
}

# OCP currently ships no test suite, so we synthesize a crude import unit test.
src_test() {
	PYTHONPATH="${S}/OCP.build" ${EPYTHON} -c \
		'from OCP.gp import gp_Vec, gp_Ax1, gp_Ax3, gp_Pnt, gp_Dir, gp_Trsf, gp_GTrsf, gp, gp_XYZ'
}

src_install() {
	python_moduleinto .
	python_domodule "${S}/OCP.build/"OCP*.so
}
