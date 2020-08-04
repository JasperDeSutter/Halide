cmake_minimum_required(VERSION 3.16)

##
# This module provides a facility for recursively converting a
# set of IMPORTED STATIC libraries to an IMPORTED OBJECT library.
#
# This is useful when a STATIC library produced by your project
# depends privately on a 3rd-party STATIC library that is tricky
# to build or distribute. Linking an OBJECT library privately to
# your STATIC library will cause those objects to be included in
# your library and CMake will drop the file dependencies on the
# 3rd-party library.
#
# It works by unpacking an IMPORTED STATIC library and recursively
# walking its INTERFACE_LINK_LIBRARIES property to unpack all other
# IMPORTED STATIC libraries.
##

function(bundle_static)
    set(options)
    set(oneValueArgs TARGET)
    set(multiValueArgs LIBRARIES)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    add_library(${ARG_TARGET} INTERFACE)
    add_library(${ARG_TARGET}.obj OBJECT IMPORTED)

    set_target_properties(${ARG_TARGET}.obj PROPERTIES IMPORTED_GLOBAL TRUE)
    target_sources(${ARG_TARGET} INTERFACE $<BUILD_INTERFACE:$<TARGET_OBJECTS:${ARG_TARGET}.obj>>)

    set(queue ${ARG_LIBRARIES})
    while (queue)
        list(POP_FRONT queue lib)
        if (VISITED_${lib})
            continue()
        endif ()
        set(VISITED_${lib} TRUE)

        if (NOT TARGET ${lib})
            target_link_libraries(${ARG_TARGET} INTERFACE ${lib})
            continue()
        endif ()

        get_property(isImported TARGET ${lib} PROPERTY IMPORTED)
        get_property(type TARGET ${lib} PROPERTY TYPE)

        if (NOT isImported OR NOT "${type}" STREQUAL "STATIC_LIBRARY")
            target_link_libraries(${ARG_TARGET} INTERFACE ${lib})
            continue()
        endif ()

        # This list should match the list of IMPORTED_ and INTERFACE_ properties documented here:
        # https://cmake.org/cmake/help/v3.16/manual/cmake-properties.7.html#properties-on-targets
        # Because these properties are copied from a static library to an object library,
        # those that do not apply to both types should be skipped.

        # IMPORTED_CONFIGURATIONS # handled below
        # IMPORTED_GLOBAL # always true
        # IMPORTED_IMPLIB(_<CONFIG>) # shared-only
        # IMPORTED_LIBNAME(_<CONFIG>) # interface-only
        # IMPORTED_LINK_DEPENDENT_LIBRARIES(_<CONFIG>) # shared-only
        # IMPORTED_LINK_INTERFACE_LANGUAGES(_<CONFIG>) # static-only
        # IMPORTED_LINK_INTERFACE_LIBRARIES(_<CONFIG>) # deprecated
        # IMPORTED_LINK_INTERFACE_MULTIPLICITY(_<CONFIG>) # static-only
        # IMPORTED_LOCATION(_<CONFIG>) # handled below
        # IMPORTED_NO_SONAME(_<CONFIG>) # shared-only
        # IMPORTED_OBJECTS(_<CONFIG>) # handled below
        # IMPORTED # checked above
        # IMPORTED_SONAME(_<CONFIG>) # shared-only
        # INTERFACE_LINK_LIBRARIES # handled below

        get_property(configs TARGET ${lib} PROPERTY IMPORTED_CONFIGURATIONS)

        transfer_same(PROPERTIES
                      IMPORTED_COMMON_LANGUAGE_RUNTIME
                      FROM ${lib} TO ${ARG_TARGET}.obj)

        transfer_same(PROPERTIES
                      INTERFACE_AUTOUIC_OPTIONS
                      INTERFACE_POSITION_INDEPENDENT_CODE
                      FROM ${lib} TO ${ARG_TARGET})

        transfer_append(PROPERTIES
                        INTERFACE_COMPILE_DEFINITIONS
                        INTERFACE_COMPILE_FEATURES
                        INTERFACE_COMPILE_OPTIONS
                        INTERFACE_INCLUDE_DIRECTORIES
                        INTERFACE_LINK_DEPENDS
                        INTERFACE_LINK_DIRECTORIES
                        INTERFACE_LINK_OPTIONS
                        INTERFACE_PRECOMPILE_HEADERS
                        INTERFACE_SOURCES
                        INTERFACE_SYSTEM_INCLUDE_DIRECTORIES
                        FROM ${lib} TO ${ARG_TARGET})

        transfer_location(CONFIGS ${configs}
                          FROM ${lib} TO ${ARG_TARGET}.obj)

        get_property(deps TARGET ${lib} PROPERTY INTERFACE_LINK_LIBRARIES)
        list(APPEND queue ${deps})
    endwhile ()
endfunction()

function(transfer_same)
    set(options)
    set(oneValueArgs FROM TO PROPERTIES)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach (p IN LISTS ARG_PROPERTIES)
        get_property(fromSet TARGET ${ARG_FROM} PROPERTY ${p} SET)
        if (NOT fromSet)
            continue()
        endif ()
        get_property(fromVal TARGET ${ARG_FROM} PROPERTY ${p})

        get_property(toSet TARGET ${ARG_TO} PROPERTY ${p} SET)
        if (NOT toSet)
            set_property(TARGET ${ARG_TO} PROPERTY ${p} ${fromVal})
        endif ()

        get_property(toVal TARGET ${ARG_TO} PROPERTY ${p})
        if (NOT "${fromVal}" STREQUAL "${toVal}")
            message(WARNING "Property ${p} does not agree between ${ARG_FROM} [${fromVal}] and ${ARG_TO} [${toVal}]")
        endif ()
    endforeach ()
endfunction()

function(transfer_append)
    set(options)
    set(oneValueArgs FROM TO PROPERTIES)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach (p IN LISTS ARG_PROPERTIES)
        get_property(fromSet TARGET ${ARG_FROM} PROPERTY ${p} SET)
        if (fromSet)
            get_property(fromVal TARGET ${ARG_FROM} PROPERTY ${p})
            set_property(TARGET ${ARG_TO} APPEND PROPERTY ${p} ${fromVal})
        endif ()
    endforeach ()
endfunction()

function(transfer_location)
    set(options)
    set(oneValueArgs FROM TO)
    set(multiValueArgs CONFIGS)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    foreach (cfg IN LISTS ARG_CONFIGS ITEMS "")
        if (cfg)
            string(TOUPPER "_${cfg}" cfg)
        endif ()
        get_property(lib TARGET ${ARG_FROM} PROPERTY "IMPORTED_LOCATION${cfg}")
        if (lib)
            unpack_static_lib(LIBRARY ${lib} OBJECTS objects)
            set_property(TARGET ${ARG_TO} APPEND PROPERTY "IMPORTED_OBJECTS${cfg}" ${objects})
        endif ()
    endforeach ()
endfunction()

function(unpack_static_lib)
    set(options)
    set(oneValueArgs LIBRARY OBJECTS)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    get_filename_component(stage "${ARG_LIBRARY}" NAME_WE)
    set(stage "${CMAKE_CURRENT_BINARY_DIR}/${stage}.obj")

    if (NOT EXISTS "${stage}")
        execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${stage}")
        execute_process(COMMAND ${CMAKE_COMMAND} -E chdir "${stage}" ${CMAKE_AR} -x "${ARG_LIBRARY}")
    endif ()

    unset(globs)
    get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
    foreach (lang IN LISTS languages)
        list(APPEND globs "${stage}/*${CMAKE_${lang}_OUTPUT_EXTENSION}")
    endforeach ()

    file(GLOB_RECURSE objects ${globs})

    set(${ARG_OBJECTS} "${objects}" PARENT_SCOPE)
endfunction()
