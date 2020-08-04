cmake_minimum_required(VERSION 3.16)

##
# This module provides a facility for recursively converting an
# IMPORTED STATIC library to an IMPORTED OBJECT library.
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

function(static_to_object)
    set(options)
    set(oneValueArgs PREFIX STATIC_TARGET OBJECT_TARGET)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (NOT TARGET ${ARG_STATIC_TARGET})
        # system library, no need to convert
        set(${ARG_OBJECT_TARGET} ${ARG_STATIC_TARGET} PARENT_SCOPE)
        return()
    endif ()

    set(target "${ARG_PREFIX}${ARG_STATIC_TARGET}")

    if (TARGET ${target})
        # already processed
        set(${ARG_OBJECT_TARGET} ${target} PARENT_SCOPE)
        return()
    endif ()

    get_property(isImported TARGET ${ARG_STATIC_TARGET} PROPERTY IMPORTED)
    get_property(type TARGET ${ARG_STATIC_TARGET} PROPERTY TYPE)

    if (NOT isImported OR NOT "${type}" STREQUAL "STATIC_LIBRARY")
        # can't convert non-imported libraries or non-static-libraries
        set(${ARG_OBJECT_TARGET} ${ARG_STATIC_TARGET} PARENT_SCOPE)
        return()
    endif ()

    # Now we know we have a target which is a static, imported target
    add_library(${target} OBJECT IMPORTED)

    # This list should match the list of IMPORTED_ and INTERFACE_ properties documented here:
    # https://cmake.org/cmake/help/v3.16/manual/cmake-properties.7.html#properties-on-targets
    # Because these properties are copied from a static library to an object library,
    # those that do not apply to both types should be skipped.

    set(transfer_properties
        IMPORTED_COMMON_LANGUAGE_RUNTIME
        # IMPORTED_CONFIGURATIONS # handled below
        # IMPORTED_GLOBAL # handled specially - can't be set to false
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
        INTERFACE_AUTOUIC_OPTIONS
        INTERFACE_COMPILE_DEFINITIONS
        INTERFACE_COMPILE_FEATURES
        INTERFACE_COMPILE_OPTIONS
        INTERFACE_INCLUDE_DIRECTORIES
        INTERFACE_LINK_DEPENDS
        INTERFACE_LINK_DIRECTORIES
        # INTERFACE_LINK_LIBRARIES # handled below
        INTERFACE_LINK_OPTIONS
        INTERFACE_POSITION_INDEPENDENT_CODE
        INTERFACE_PRECOMPILE_HEADERS
        INTERFACE_SOURCES
        INTERFACE_SYSTEM_INCLUDE_DIRECTORIES)

    foreach (p IN LISTS transfer_properties)
        get_property(isSet TARGET ${ARG_STATIC_TARGET} PROPERTY ${p} SET)
        if (isSet)
            get_property(pVal TARGET ${ARG_STATIC_TARGET} PROPERTY ${p})
            set_property(TARGET ${target} PROPERTY ${p} ${pVal})
        endif ()
    endforeach ()

    get_property(isGlobal TARGET ${ARG_STATIC_TARGET} PROPERTY IMPORTED_GLOBAL)
    if (isGlobal)
        set_property(TARGET ${target} PROPERTY IMPORTED_GLOBAL ${isGlobal})
    endif ()

    transfer_location(FROM ${ARG_STATIC_TARGET} TO ${target})

    get_property(configs TARGET ${ARG_STATIC_TARGET} PROPERTY IMPORTED_CONFIGURATIONS)
    foreach (cfg IN LISTS configs)
        transfer_location(FROM ${ARG_STATIC_TARGET} TO ${target}
                          CONFIG ${cfg})
    endforeach ()

    get_property(deps TARGET ${ARG_STATIC_TARGET} PROPERTY INTERFACE_LINK_LIBRARIES)
    foreach (dep IN LISTS deps)
        static_to_object(PREFIX ${ARG_PREFIX}
                         STATIC_TARGET ${dep}
                         OBJECT_TARGET dep_obj)
        target_link_libraries(${target} INTERFACE ${dep_obj})
    endforeach ()

    set(${ARG_OBJECT_TARGET} ${target} PARENT_SCOPE)
endfunction()

function(transfer_location)
    set(options)
    set(oneValueArgs FROM TO CONFIG)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    if (ARG_CONFIG)
        string(TOUPPER "_${ARG_CONFIG}" ARG_CONFIG)
    endif ()

    set(location_prop "IMPORTED_LOCATION${ARG_CONFIG}")
    set(objects_prop "IMPORTED_OBJECTS${ARG_CONFIG}")

    get_property(isSet TARGET ${ARG_FROM} PROPERTY ${location_prop} SET)
    if (isSet)
        get_property(lib TARGET ${ARG_FROM} PROPERTY ${location_prop})
        unpack_static_lib(LIBRARY ${lib} OBJECTS objects)

        set_property(TARGET ${ARG_TO} PROPERTY "${objects_prop}" ${objects})
    endif ()
endfunction()

function(unpack_static_lib)
    set(options)
    set(oneValueArgs LIBRARY OBJECTS)
    set(multiValueArgs)
    cmake_parse_arguments(ARG "${options}" "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

    get_filename_component(stage "${ARG_LIBRARY}" NAME_WE)
    set(stage "${CMAKE_CURRENT_BINARY_DIR}/${stage}.obj")
    execute_process(COMMAND ${CMAKE_COMMAND} -E make_directory "${stage}")

    if (NOT "${CMAKE_AR}" MATCHES "ar|AR")
        message(FATAL_ERROR "Archive tool ${CMAKE_AR} not supported by StaticToObject!")
    endif ()
    execute_process(COMMAND ${CMAKE_COMMAND} -E chdir "${stage}" ${CMAKE_AR} -x "${ARG_LIBRARY}")

    unset(globs)
    get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
    foreach (lang IN LISTS languages)
        list(APPEND globs "${stage}/*${CMAKE_${lang}_OUTPUT_EXTENSION}")
    endforeach ()

    file(GLOB_RECURSE objects ${globs})

    set(${ARG_OBJECTS} "${objects}" PARENT_SCOPE)
endfunction()
