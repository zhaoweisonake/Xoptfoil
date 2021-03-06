!  This file is part of XOPTFOIL.

!  XOPTFOIL is free software: you can redistribute it and/or modify
!  it under the terms of the GNU General Public License as published by
!  the Free Software Foundation, either version 3 of the License, or
!  (at your option) any later version.

!  XOPTFOIL is distributed in the hope that it will be useful,
!  but WITHOUT ANY WARRANTY; without even the implied warranty of
!  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
!  GNU General Public License for more details.

!  You should have received a copy of the GNU General Public License
!  along with XOPTFOIL.  If not, see <http://www.gnu.org/licenses/>.

!  Copyright (C) 2014 -- 2016 Daniel Prosser

module input_output

! Module with subroutines for reading and writing of files

  implicit none

  contains

!=============================================================================80
!
! Subroutine to read inputs from namelist file
!
!=============================================================================80
subroutine read_inputs(input_file, search_type, global_search, local_search,   &
                       seed_airfoil, airfoil_file, nfunctions_top,             &
                       nfunctions_bot, restart, restart_write_freq,            &
                       constrained_dvs, naca_options, pso_options, ga_options, &
                       ds_options, matchfoil_file)

  use vardef
  use particle_swarm,     only : pso_options_type
  use genetic_algorithm,  only : ga_options_type
  use simplex_search,     only : ds_options_type
  use airfoil_operations, only : my_stop
  use airfoil_evaluation, only : xfoil_options, xfoil_geom_options
  use naca,               only : naca_options_type
 
  character(*), intent(in) :: input_file
  character(80), intent(out) :: search_type, global_search, local_search,      &
                                seed_airfoil, airfoil_file, matchfoil_file
  integer, intent(out) :: nfunctions_top, nfunctions_bot
  integer, dimension(:), allocatable, intent(inout) :: constrained_dvs
  type(naca_options_type), intent(out) :: naca_options
  type(pso_options_type), intent(out) :: pso_options
  type(ga_options_type), intent(out) :: ga_options
  type(ds_options_type), intent(out) :: ds_options

  logical :: viscous_mode, silent_mode, fix_unconverged, feasible_init,        &
             reinitialize, restart, write_designs, reflexed
  integer :: restart_write_freq, pso_pop, pso_maxit, simplex_maxit, bl_maxit,  &
             npan, feasible_init_attempts
  integer :: ga_pop, ga_maxit
  double precision :: maxt, xmaxt, maxc, xmaxc, design_cl, a, leidx
  double precision :: pso_tol, simplex_tol, ncrit, xtript, xtripb, vaccel
  double precision :: cvpar, cterat, ctrrat, xsref1, xsref2, xpref1, xpref2
  double precision :: feasible_limit
  double precision :: ga_tol, parent_fraction, roulette_selection_pressure,    &
                      tournament_fraction, crossover_range_factor,             &
                      mutant_probability, chromosome_mutation_rate,            &
                      mutation_range_factor
  integer :: nbot_actual, nmoment_constraint, nxtr_opt
  integer :: i, iunit, ioerr, iostat1, counter, idx
  character(30) :: text
  character(3) :: family
  character(10) :: pso_convergence_profile, parents_selection_method
  character :: choice

  namelist /optimization_options/ search_type, global_search, local_search,    &
            seed_airfoil, airfoil_file, shape_functions, nfunctions_top,       &
            nfunctions_bot, initial_perturb, min_bump_width, restart,          &
            restart_write_freq, write_designs
  namelist /operating_conditions/ noppoint, op_mode, op_point, reynolds, mach, &
            use_flap, x_flap, y_flap, y_flap_spec, flap_selection,             &
            flap_degrees, weighting, optimization_type, ncrit_pt
  namelist /constraints/ min_thickness, max_thickness, moment_constraint_type, &
                         min_moment, min_te_angle, check_curvature,            &
                         max_curv_reverse_top, max_curv_reverse_bot,           &
                         curv_threshold, symmetrical, min_flap_degrees,        &
                         max_flap_degrees, min_camber, max_camber
  namelist /naca_airfoil/ family, maxt, xmaxt, maxc, xmaxc, design_cl, a,      &
                          leidx, reflexed
  namelist /initialization/ feasible_init, feasible_limit,                     &
                            feasible_init_attempts
  namelist /particle_swarm_options/ pso_pop, pso_tol, pso_maxit,               &
                                    pso_convergence_profile
  namelist /genetic_algorithm_options/ ga_pop, ga_tol, ga_maxit,               &
            parents_selection_method, parent_fraction,                         &
            roulette_selection_pressure, tournament_fraction,                  &
            crossover_range_factor, mutant_probability,                        &
            chromosome_mutation_rate, mutation_range_factor
  namelist /simplex_options/ simplex_tol, simplex_maxit
  namelist /xfoil_run_options/ ncrit, xtript, xtripb, viscous_mode,            &
            silent_mode, bl_maxit, vaccel, fix_unconverged, reinitialize
  namelist /xfoil_paneling_options/ npan, cvpar, cterat, ctrrat, xsref1,       &
            xsref2, xpref1, xpref2
  namelist /matchfoil_options/ match_foils, matchfoil_file

! Open input file

  iunit = 12
  open(unit=iunit, file=input_file, status='old', iostat=ioerr)
  if (ioerr /= 0)                                                              &
    call my_stop('Could not find input file '//trim(input_file)//'.')

! Set defaults for main namelist options

  search_type = 'global_and_local'
  global_search = 'particle_swarm'
  local_search = 'simplex'
  seed_airfoil = 'naca'
  shape_functions = 'hicks-henne'
  min_bump_width = 0.1d0
  nfunctions_top = 4
  nfunctions_bot = 4
  initial_perturb = 0.025d0
  restart = .false.
  restart_write_freq = 20
  write_designs = .true.

! Read main namelist options

  rewind(iunit)
  read(iunit, iostat=iostat1, nml=optimization_options)
  call namelist_check('optimization_options', iostat1, 'warn')

! Error checking and setting search algorithm options

  if (trim(search_type) /= 'global_and_local' .and. trim(search_type) /=       &
      'global' .and. trim(search_type) /= 'local')                             &
    call my_stop("search_type must be 'global_and_local', 'global', "//   &
                 "or 'local'.")

! Set defaults for operating conditions and constraints

  noppoint = 1
  use_flap = .false.
  x_flap = 0.75d0
  y_flap = 0.d0
  y_flap_spec = 'y/c'
  op_mode(:) = 'spec-cl'
  op_point(:) = 0.d0
  optimization_type(:) = 'min-drag'
  reynolds(:) = 1.0D+05
  mach(:) = 0.d0
  flap_selection(:) = 'specify'
  flap_degrees(:) = 0.d0
  weighting(:) = 1.d0
  ncrit_pt(:) = -1.d0

  min_thickness = 0.06d0
  max_thickness = 1000.d0
  min_camber = -0.1d0
  max_camber = 0.1d0
  moment_constraint_type(:) = 'none'
  min_moment(:) = -1.d0
  min_te_angle = 5.d0
  check_curvature = .false.
  max_curv_reverse_top = 1
  max_curv_reverse_bot = 1
  curv_threshold = 0.30d0
  symmetrical = .false.
  min_flap_degrees = -5.d0
  max_flap_degrees = 15.d0

! Read operating conditions and constraints

  rewind(iunit)
  read(iunit, iostat=iostat1, nml=operating_conditions)
  call namelist_check('operating_conditions', iostat1, 'stop')
  rewind(iunit)
  read(iunit, iostat=iostat1, nml=constraints)
  call namelist_check('constraints', iostat1, 'stop')

! Store operating points where flap setting will be optimized

  nflap_optimize = 0
  if (use_flap .and. (.not. match_foils)) then
    do i = 1, noppoint
      if (flap_selection(i) == 'optimize') then
        nflap_optimize = nflap_optimize + 1
        flap_optimize_points(nflap_optimize) = i
      end if
    end do
  end if

! Normalize weightings for operating points

  weighting = weighting/sum(weighting(1:noppoint))

! Ask about removing pitching moment constraints for symmetrical optimization

  if (symmetrical) then
    nmoment_constraint = 0
    do i = 1, noppoint
      if (trim(moment_constraint_type(i)) /= 'none')                           &
        nmoment_constraint = nmoment_constraint + 1
    end do
    
    if (nmoment_constraint > 0) choice = ask_moment_constraints()
    if (choice == 'y') moment_constraint_type(:) = 'none'
  end if

! Set defaults for naca airfoil options
 
  family = '4'
  maxt = 0.1d0
  xmaxt = 0.3d0
  maxc = 0.d0
  xmaxc = 0.3d0
  design_cl = 0.3d0
  a = 1.d0
  leidx = 6.d0
  reflexed = .false.

! Read naca airfoil options and put them into derived type

  if ( (seed_airfoil == 'naca') .or. (seed_airfoil == 'NACA') .or.             &
       (seed_airfoil == 'Naca') ) then
    rewind(iunit)
    read(iunit, iostat=iostat1, nml=naca_airfoil)
    call namelist_check('naca_airfoil', iostat1, 'warn')

    naca_options%family = family
    naca_options%maxt = maxt
    naca_options%xmaxt = xmaxt
    naca_options%maxc = maxc
    naca_options%xmaxc = xmaxc
    naca_options%design_cl = design_cl
    naca_options%a = a
    naca_options%leidx = leidx
    naca_options%reflexed = reflexed
  end if

! Set default initialization options

  feasible_init = .true.
  feasible_limit = 5.0D+04
  feasible_init_attempts = 1000

! Read initialization parameters

  rewind(iunit)
  read(iunit, iostat=iostat1, nml=initialization)
  call namelist_check('initialization', iostat1, 'warn')

! Set default particle swarm options

  pso_pop = 40
  pso_tol = 1.D-04
  pso_maxit = 700
  pso_convergence_profile = 'exhaustive'

! Set default genetic algorithm options

  ga_pop = 80
  ga_tol = 1.D-04
  ga_maxit = 700
  parents_selection_method = 'tournament'
  parent_fraction = 0.5d0
  roulette_selection_pressure = 8.d0
  tournament_fraction = 0.025d0
  crossover_range_factor = 0.5d0
  mutant_probability = 0.4d0
  chromosome_mutation_rate = 0.01d0
  mutation_range_factor = 0.2d0

! Set default simplex search options

  simplex_tol = 1.0D-05
  simplex_maxit = 1000

  if (trim(search_type) == 'global_and_local' .or. trim(search_type) ==        &
      'global') then

!   The number of bottom shape functions actually used (0 for symmetrical)

    if (symmetrical) then
      nbot_actual = 0
    else
      nbot_actual = nfunctions_bot
    end if
  
!   Set design variables with side constraints

    if (trim(shape_functions) == 'naca') then

!     For NACA, we will only constrain the flap deflection

      allocate(constrained_dvs(nflap_optimize))
      counter = 0
      do i = nfunctions_top + nbot_actual + 1,                                 &
             nfunctions_top + nbot_actual + nflap_optimize
        counter = counter + 1
        constrained_dvs(counter) = i
      end do
          
    else

!     For Hicks-Henne, also constrain bump locations and width

      allocate(constrained_dvs(2*nfunctions_top + 2*nbot_actual +              &
                               nflap_optimize))
      counter = 0
      do i = 1, nfunctions_top + nbot_actual
        counter = counter + 1
        idx = 3*(i-1) + 2      ! DV index of bump location, shape function i
        constrained_dvs(counter) = idx
        counter = counter + 1
        idx = 3*(i-1) + 3      ! Index of bump width, shape function i
        constrained_dvs(counter) = idx
      end do
      do i = 3*(nfunctions_top + nbot_actual) + 1,                             &
             3*(nfunctions_top + nbot_actual) + nflap_optimize
        counter = counter + 1
        constrained_dvs(counter) = i
      end do

    end if

    if (trim(global_search) == 'particle_swarm') then

!     Read PSO options and put them into derived type

      rewind(iunit)
      read(iunit, iostat=iostat1, nml=particle_swarm_options)
      call namelist_check('particle_swarm_options', iostat1, 'warn')
      pso_options%pop = pso_pop
      pso_options%tol = pso_tol
      pso_options%maxspeed = initial_perturb
      pso_options%maxit = pso_maxit
      pso_options%convergence_profile = pso_convergence_profile
      pso_options%feasible_init = feasible_init
      pso_options%feasible_limit = feasible_limit
      pso_options%feasible_init_attempts = feasible_init_attempts
      pso_options%write_designs = write_designs
      if (.not. match_foils) then
        pso_options%relative_fmin_report = .true.
      else
        pso_options%relative_fmin_report = .false.
      end if

    else if (trim(global_search) == 'genetic_algorithm') then

!     Read genetic algorithm options and put them into derived type

      rewind(iunit)
      read(iunit, iostat=iostat1, nml=genetic_algorithm_options)
      call namelist_check('genetic_algorithm_options', iostat1, 'warn')
      ga_options%pop = ga_pop
      ga_options%tol = ga_tol
      ga_options%maxit = ga_maxit
      ga_options%parents_selection_method = parents_selection_method
      ga_options%parent_fraction = parent_fraction
      ga_options%roulette_selection_pressure = roulette_selection_pressure
      ga_options%tournament_fraction = tournament_fraction
      ga_options%crossover_range_factor = crossover_range_factor
      ga_options%mutant_probability = mutant_probability
      ga_options%chromosome_mutation_rate = chromosome_mutation_rate
      ga_options%mutation_range_factor = mutation_range_factor
      ga_options%feasible_init = feasible_init
      ga_options%feasible_limit = feasible_limit
      ga_options%feasible_init_attempts = feasible_init_attempts
      ga_options%write_designs = write_designs
      if (.not. match_foils) then
        ga_options%relative_fmin_report = .true.
      else
        ga_options%relative_fmin_report = .false.
      end if

    else
      call my_stop("Global search type '"//trim(global_search)//               &
                   "' is not available.")
    end if
  end if

  if (trim(search_type) == 'global_and_local' .or. trim(search_type) ==        &
      'local') then

    if (trim(local_search) == 'simplex') then

!     Read simplex search options and put them into derived type

      rewind(iunit)
      read(iunit, iostat=iostat1, nml=simplex_options)
      call namelist_check('simplex_options', iostat1, 'warn')
      ds_options%tol = simplex_tol
      ds_options%maxit = simplex_maxit
      ds_options%write_designs = write_designs
      if (.not. match_foils) then
        ds_options%relative_fmin_report = .true.
      else
        ds_options%relative_fmin_report = .false.
      end if

    else
      call my_stop("Local search type '"//trim(local_search)//   &
                   "' is not available.")
    end if

  end if 

! Set default xfoil aerodynamics and paneling options

  ncrit = 9.d0
  xtript = 1.d0
  xtripb = 1.d0
  viscous_mode = .true.
  silent_mode = .true.
  bl_maxit = 100
  vaccel = 0.01d0
  fix_unconverged = .true.
  reinitialize = .true.

  npan = 160
  cvpar = 1.d0
  cterat = 0.15d0
  ctrrat = 0.2d0
  xsref1 = 1.d0
  xsref2 = 1.d0
  xpref1 = 1.d0
  xpref2 = 1.d0

! Read xfoil options

  rewind(iunit)
  read(iunit, iostat=iostat1, nml=xfoil_run_options)
  call namelist_check('xfoil_run_options', iostat1, 'warn')
  rewind(iunit)
  read(iunit, iostat=iostat1, nml=xfoil_paneling_options)
  call namelist_check('xfoil_paneling_options', iostat1, 'warn')

! Ask about removing turbulent trips for max-xtr optimization

  nxtr_opt = 0
  if ( (xtript < 1.d0) .or. (xtripb < 1.d0) ) then
    do i = 1, noppoint
      if (trim(optimization_type(i)) == "max-xtr") nxtr_opt = nxtr_opt + 1
    end do
 
    if (nxtr_opt > 0) choice = ask_forced_transition()
    if (choice == 'y') then
      xtript = 1.d0
      xtripb = 1.d0
    end if
  end if

! Put xfoil options into derived types

  xfoil_options%ncrit = ncrit
  xfoil_options%xtript = xtript
  xfoil_options%xtripb = xtripb
  xfoil_options%viscous_mode = viscous_mode
  xfoil_options%silent_mode = silent_mode
  xfoil_options%maxit = bl_maxit
  xfoil_options%vaccel = vaccel
  xfoil_options%fix_unconverged = fix_unconverged
  xfoil_options%reinitialize = reinitialize

  xfoil_geom_options%npan = npan
  xfoil_geom_options%cvpar = cvpar
  xfoil_geom_options%cterat = cterat
  xfoil_geom_options%ctrrat = ctrrat
  xfoil_geom_options%xsref1 = xsref1
  xfoil_geom_options%xsref2 = xsref2
  xfoil_geom_options%xpref1 = xpref1
  xfoil_geom_options%xpref2 = xpref2

! Set per-point ncrit if not specified in namelist

  do i = 1, noppoint
    if (ncrit_pt(i) == -1.d0) ncrit_pt(i) = ncrit
  end do

! Option to match seed airfoil to another instead of aerodynamic optimization

  match_foils = .false.
  matchfoil_file = 'none'
  read(iunit, iostat=iostat1, nml=matchfoil_options)
  call namelist_check('matchfoil_options', iostat1, 'warn')

! Close the input file

  close(iunit)

! Echo namelist options for checking purposes

  write(*,*)
  write(*,*) 'Echoing program options:'
  write(*,*)

! Optimization options namelist

  write(*,'(A)') " &optimization_options"
  write(*,*) " search_type = '"//trim(search_type)//"'"
  write(*,*) " global_search = '"//trim(global_search)//"'"
  write(*,*) " local_search = '"//trim(local_search)//"'"
  write(*,*) " seed_airfoil = '"//trim(seed_airfoil)//"'"
  write(*,*) " airfoil_file = '"//trim(airfoil_file)//"'"
  write(*,*) " shape_functions = '"//trim(shape_functions)//"'"
  write(*,*) " min_bump_width = ", min_bump_width
  write(*,*) " nfunctions_top = ", nfunctions_top
  write(*,*) " nfunctions_bot = ", nfunctions_bot
  write(*,*) " initial_perturb = ", initial_perturb
  write(*,*) " restart = ", restart
  write(*,*) " restart_write_freq = ", restart_write_freq
  write(*,*) " write_designs = ", write_designs
  write(*,'(A)') " /"
  write(*,*)

! Operating conditions namelist

  write(*,'(A)') " &operating_conditions"
  write(*,*) " noppoint = ", noppoint
  write(*,*) " use_flap = ", use_flap
  write(*,*) " x_flap = ", x_flap
  write(*,*) " y_flap = ", y_flap
  write(*,*) " y_flap_spec = "//trim(y_flap_spec)
  write(*,*)
  do i = 1, noppoint
    write(text,*) i
    text = adjustl(text)
    write(*,*) " optimization_type("//trim(text)//") = '"//                    &
               trim(optimization_type(i))//"'"
    write(*,*) " op_mode("//trim(text)//") = '"//trim(op_mode(i))//"'"
    write(*,*) " op_point("//trim(text)//") = ", op_point(i)
    write(*,'(A,es17.8)') "  reynolds("//trim(text)//") = ", reynolds(i)
    write(*,*) " mach("//trim(text)//") = ", mach(i)
    write(*,*) " flap_selection("//trim(text)//") = '"//                       &
               trim(flap_selection(i))//"'"
    write(*,*) " flap_degrees("//trim(text)//") = ", flap_degrees(i)
    write(*,*) " weighting("//trim(text)//") = ", weighting(i)
    if (ncrit_pt(i) /= -1.d0)                                                  &
      write(*,*) " ncrit_pt("//trim(text)//") = ", ncrit_pt(i)
    if (i < noppoint) write(*,*)
  end do
  write(*,'(A)') " /"
  write(*,*)

! Constraints namelist

  write(*,'(A)') " &constraints"
  write(*,*) " min_thickness = ", min_thickness
  write(*,*) " max_thickness = ", max_thickness
  do i = 1, noppoint
    write(text,*) i
    text = adjustl(text)
    write(*,*) " moment_constraint_type("//trim(text)//") = "//                &
               trim(moment_constraint_type(i))
    write(*,*) " min_moment("//trim(text)//") = ", min_moment(i)
  end do
  write(*,*) " min_te_angle = ", min_te_angle
  write(*,*) " check_curvature = ", check_curvature
  write(*,*) " max_curv_reverse_top = ", max_curv_reverse_top
  write(*,*) " max_curv_reverse_bot = ", max_curv_reverse_bot
  write(*,*) " curv_threshold = ", curv_threshold
  write(*,*) " symmetrical = ", symmetrical
  write(*,*) " min_flap_degrees = ", min_flap_degrees
  write(*,*) " max_flap_degrees = ", max_flap_degrees
  write(*,*) " min_camber = ", min_camber
  write(*,*) " max_camber = ", max_camber
  write(*,'(A)') " /"
  write(*,*)

! NACA namelist

  write(*,'(A)') " &naca"
  write(*,*) " family = "//trim(adjustl(family))
  write(*,*) " maxt = ", maxt
  write(*,*) " xmaxt = ", xmaxt
  write(*,*) " maxc = ", maxc
  write(*,*) " xmaxc = ", xmaxc
  write(*,*) " design_cl = ", design_cl
  write(*,*) " a = ", a
  write(*,*) " leidx = ", leidx
  write(*,*) " reflexed = ", reflexed
  write(*,'(A)') " /"
  write(*,*)

! Initialization namelist

  write(*,'(A)') " &initialization"
  write(*,*) " feasible_init = ", feasible_init
  write(*,*) " feasible_limit = ", feasible_limit
  write(*,*) " feasible_init_attempts = ", feasible_init_attempts
  write(*,'(A)') " /"
  write(*,*)

! Optimizer namelists

  if (trim(search_type) == 'global_and_local' .or. trim(search_type) ==        &
      'global') then

    if (trim(global_search) == 'particle_swarm') then

!     Particle swarm namelist

      write(*,'(A)') " &particle_swarm_options"
      write(*,*) " pso_pop = ", pso_options%pop
      write(*,*) " pso_tol = ", pso_options%tol
      write(*,*) " pso_maxit = ", pso_options%maxit
      write(*,*) " pso_convergence_profile = ", pso_options%convergence_profile
      write(*,'(A)') " /"
      write(*,*)

    else if (trim(global_search) == 'genetic_algorithm') then

!     Genetic algorithm options

      write(*,'(A)') " &genetic_algorithm_options"
      write(*,*) " ga_pop = ", ga_options%pop
      write(*,*) " ga_tol = ", ga_options%tol
      write(*,*) " ga_maxit = ", ga_options%maxit
      write(*,*) " parents_selection_method = ",                               &
                 ga_options%parents_selection_method
      write(*,*) " parent_fraction = ", ga_options%parent_fraction 
      write(*,*) " roulette_selection_pressure = ",                            &
                 ga_options%roulette_selection_pressure
      write(*,*) " tournament_fraction = " , ga_options%tournament_fraction
      write(*,*) " crossover_range_factor = ", ga_options%crossover_range_factor
      write(*,*) " mutant_probability = ", ga_options%mutant_probability
      write(*,*) " chromosome_mutation_rate = ",                               &
                 ga_options%chromosome_mutation_rate
      write(*,*) " mutation_range_factor = ", ga_options%mutation_range_factor
      write(*,'(A)') " /"
      write(*,*)

    end if

  end if

  if (trim(search_type) == 'global_and_local' .or. trim(search_type) ==        &
      'local') then

    if(trim(local_search) == 'simplex') then

!     Simplex search namelist

      write(*,'(A)') " &simplex_options"
      write(*,*) " simplex_tol = ", ds_options%tol
      write(*,*) " simplex_maxit = ", ds_options%maxit
      write(*,'(A)') " /"
      write(*,*)

    end if

  end if

! Xfoil run options namelist

  write(*,'(A)') " &xfoil_run_options"
  write(*,*) " ncrit = ", xfoil_options%ncrit
  write(*,*) " xtript = ", xfoil_options%xtript
  write(*,*) " xtripb = ", xfoil_options%xtripb
  write(*,*) " viscous_mode = ", xfoil_options%viscous_mode
  write(*,*) " silent_mode = ", xfoil_options%silent_mode
  write(*,*) " bl_maxit = ", xfoil_options%maxit
  write(*,*) " vaccel = ", xfoil_options%vaccel
  write(*,*) " fix_unconverged = ", xfoil_options%fix_unconverged
  write(*,*) " reinitialize = ", xfoil_options%reinitialize
  write(*,'(A)') " /"
  write(*,*)

! Xfoil paneling options namelist

  write(*,'(A)') " &xfoil_paneling_options"
  write(*,*) " npan = ", xfoil_geom_options%npan
  write(*,*) " cvpar = ", xfoil_geom_options%cvpar
  write(*,*) " cterat = ", xfoil_geom_options%cterat
  write(*,*) " ctrrat = ", xfoil_geom_options%ctrrat
  write(*,*) " xsref1 = ", xfoil_geom_options%xsref1
  write(*,*) " xsref2 = ", xfoil_geom_options%xsref2
  write(*,*) " xpref1 = ", xfoil_geom_options%xpref1
  write(*,*) " xpref2 = ", xfoil_geom_options%xpref2
  write(*,'(A)') " /"
  write(*,*)

! Matchfoil options

  write(*,'(A)') " &matchfoil_options"
  write(*,*) " match_foils = ", match_foils
  write(*,*) " matchfoil_file = '"//trim(matchfoil_file)//"'"
  write(*,'(A)') " /"
  write(*,*)

! Check that inputs are reasonable

! Optimization settings

  if (trim(seed_airfoil) /= 'from_file' .and.                                  &
      trim(seed_airfoil) /= 'naca')                                            &
    call my_stop("seed_airfoil must be 'from_file' or 'naca'.")
  if (trim(shape_functions) /= 'hicks-henne' .and.                             &
      trim(shape_functions) /= 'naca')                                         &
    call my_stop("shape_functions must be 'hicks-henne' or 'naca'.")
  if (nfunctions_top < 0)                                                      &
    call my_stop("nfunctions_top must be >= 0.")
  if (nfunctions_bot < 0)                                                      &
    call my_stop("nfunctions_bot must be >= 0.")
  if (initial_perturb <= 0.d0)                                                 &
    call my_stop("initial_perturb must be > 0.")
  if (min_bump_width <= 0.d0)                                                  &
    call my_stop("min_bump_width must be > 0.")

! Operating points

  if (noppoint < 1) call my_stop("noppoint must be > 0.")
  if ((use_flap) .and. (x_flap <= 0.0)) call my_stop("x_flap must be > 0.")
  if ((use_flap) .and. (x_flap >= 1.0)) call my_stop("x_flap must be < 1.")
  if ((use_flap) .and. (y_flap_spec /= 'y/c') .and. (y_flap_spec /= 'y/t'))    &
    call my_stop("y_flap_spec must be 'y/c' or 'y/t'.")

  do i = 1, noppoint
    if (trim(op_mode(i)) /= 'spec-cl' .and. trim(op_mode(i)) /= 'spec-al')     &
      call my_stop("op_mode must be 'spec-al' or 'spec-cl'.")
    if (reynolds(i) <= 0.d0) call my_stop("reynolds must be > 0.")
    if (mach(i) < 0.d0) call my_stop("mach must be >= 0.")
    if (trim(flap_selection(i)) /= 'specify' .and.                             &
        trim(flap_selection(i)) /= 'optimize')                                 &
      call my_stop("flap_selection must be 'specify' or 'optimize'.")
    if (flap_degrees(i) < -90.d0) call my_stop("flap_degrees must be > -90.")
    if (flap_degrees(i) > 90.d0) call my_stop("flap_degrees must be < 90.")
    if (weighting(i) <= 0.d0) call my_stop("weighting must be > 0.")
    if (trim(optimization_type(i)) /= 'min-drag' .and.                         &
      trim(optimization_type(i)) /= 'max-glide' .and.                          &
      trim(optimization_type(i)) /= 'min-sink' .and.                           &
      trim(optimization_type(i)) /= 'max-lift' .and.                           &
      trim(optimization_type(i)) /= 'max-xtr' .and.                            &
      trim(optimization_type(i)) /= 'max-lift-slope')                          &
      call my_stop("optimization_type must be 'min-drag', 'max-glide', "//     &
                   "min-sink', 'max-lift', 'max-xtr', or 'max-lift-slope'.")
    if (ncrit_pt(i) <= 0.d0) call my_stop("ncrit_pt must be > 0 or -1.")
  end do

! Constraints

  if (min_thickness <= 0.d0) call my_stop("min_thickness must be > 0.")
  if (max_thickness <= 0.d0) call my_stop("max_thickness must be > 0.")
  do i = 1, noppoint
    if (trim(moment_constraint_type(i)) /= 'use_seed' .and.                    &
      trim(moment_constraint_type(i)) /= 'specify' .and.                       &
      trim(moment_constraint_type(i)) /= 'none')                               &
      call my_stop("moment_constraint_type must be 'use_seed', 'specify', "//  &
                 "or 'none'.")
  end do
  if (min_te_angle < 0.d0) call my_stop("min_te_angle must be >= 0.")
  if (check_curvature .and. (curv_threshold <= 0.d0))                          &
    call my_stop("curv_threshold must be > 0.")
  if (check_curvature .and. (max_curv_reverse_top < 0))                        &
    call my_stop("max_curv_reverse_top must be >= 0.")
  if (check_curvature .and. (max_curv_reverse_bot < 0))                        &
    call my_stop("max_curv_reverse_bot must be >= 0.")
  if (symmetrical)                                                             &
    write(*,*) "Mirroring top half of seed airfoil for symmetrical constraint."
  if (min_flap_degrees >= max_flap_degrees)                                    &
    call my_stop("min_flap_degrees must be < max_flap_degrees.")
  if (min_flap_degrees <= -90.d0)                                              &
    call my_stop("min_flap_degrees must be > -90.")
  if (max_flap_degrees >= 90.d0)                                               &
    call my_stop("max_flap_degrees must be < 90.")
  if (min_camber >= max_camber)                                                &
    call my_stop("min_camber must be < max_camber.")

! Naca airfoil options

  select case (adjustl(family))
    case ('4', '4M', '5', '63', '64', '65', '66', '67', '63A', '64A', '65A')
      continue
    case default
      call my_stop("Unrecognized NACA airfoil family.")
  end select
  if (maxt <= 0.d0) call my_stop("maxt must be > 0.")
  if ( (xmaxt < 0.d0) .or. (xmaxt > 1.d0) )                                    &
    call my_stop("xmaxt must be >= 0 and <= 1.")
  if ( (xmaxc < 0.d0) .or. (xmaxc > 1.d0) )                                    &
    call my_stop("xmaxc must be >= 0 and <= 1.")
  if ( (a < 0.d0) .or. (a > 1.d0) )                                            &
    call my_stop("a must be >= 0 and <= 1.")
  if (leidx <= 0.d0) call my_stop("leidx must be > 0.")

! Initialization options
    
  if ((feasible_limit <= 0.d0) .and. feasible_init)                            &
    call my_stop("feasible_limit must be > 0.")
  if ((feasible_init_attempts < 1) .and. feasible_init)                        &
    call my_stop("feasible_init_attempts must be > 0.")

! Optimizer options

  if (trim(search_type) == 'global' .or.                                       &
       trim(search_type) == 'global_and_local') then

    if (trim(global_search) == 'particle_swarm') then

!     Particle swarm options

      if (pso_pop < 1) call my_stop("pso_pop must be > 0.")
      if (pso_tol <= 0.d0) call my_stop("pso_tol must be > 0.")
      if (pso_maxit < 1) call my_stop("pso_maxit must be > 0.")  
      if ( (trim(pso_convergence_profile) /= "quick") .and.                    &
           (trim(pso_convergence_profile) /= "exhaustive") )                   &
        call my_stop("pso_convergence_profile must be 'exhaustive' "//&
                     "or 'quick'.")

    else if (trim(global_search) == 'genetic_algorithm') then

!     Genetic algorithm options

      if (ga_pop < 1) call my_stop("ga_pop must be > 0.")
      if (ga_tol <= 0.d0) call my_stop("ga_tol must be > 0.")
      if (ga_maxit < 1) call my_stop("ga_maxit must be > 0.")
      if ( (trim(parents_selection_method) /= "roulette") .and.                &
           (trim(parents_selection_method) /= "tournament") .and.              &
           (trim(parents_selection_method) /= "random") )                      &
        call my_stop("parents_selection_method must be 'roulette', "//&
                     "'tournament', or 'random'.")
      if ( (parent_fraction <= 0.d0) .or. (parent_fraction > 1.d0) )           &
        call my_stop("parent_fraction must be > 0 and <= 1.")
      if (roulette_selection_pressure <= 0.d0)                                 &
        call my_stop("roulette_selection_pressure must be > 0.")
      if ( (tournament_fraction <= 0.d0) .or. (tournament_fraction > 1.d0) )   &
        call my_stop("tournament_fraction must be > 0 and <= 1.")
      if (crossover_range_factor < 0.d0)                                       &
        call my_stop("crossover_range_factor must be >= 0.")
      if ( (mutant_probability < 0.d0) .or. (mutant_probability > 1.d0) )      &
        call my_stop("mutant_probability must be >= 0 and <= 1.") 
      if (chromosome_mutation_rate < 0.d0)                                     &
        call my_stop("chromosome_mutation_rate must be >= 0.")
      if (mutation_range_factor < 0.d0)                                        &
        call my_stop("mutation_range_factor must be >= 0.")

    end if

  end if

  if (trim(search_type) == 'local' .or.                                        &
       trim(search_type) == 'global_and_local') then

!   Simplex options

    if (simplex_tol <= 0.d0) call my_stop("simplex_tol must be > 0.")
    if (simplex_maxit < 1) call my_stop("simplex_maxit must be > 0.")  
  
  end if

! XFoil run options

  if (ncrit < 0.d0) call my_stop("ncrit must be >= 0.")
  if (xtript < 0.d0 .or. xtript > 1.d0)                                        &
    call my_stop("xtript must be >= 0. and <= 1.")
  if (xtripb < 0.d0 .or. xtripb > 1.d0)                                        &
    call my_stop("xtripb must be >= 0. and <= 1.")
  if (bl_maxit < 1) call my_stop("bl_maxit must be > 0.")
  if (vaccel < 0.d0) call my_stop("vaccel must be >= 0.")
  
! XFoil paneling options

  if (npan < 20) call my_stop("npan must be >= 20.")
  if (cvpar <= 0.d0) call my_stop("cvpar must be > 0.")
  if (cterat <= 0.d0) call my_stop("cterat must be > 0.")
  if (ctrrat <= 0.d0) call my_stop("ctrrat must be > 0.")
  if (xsref1 < 0.d0) call my_stop("xsref1 must be >= 0.")
  if (xsref2 < xsref1) call my_stop("xsref2 must be >= xsref1")
  if (xsref2 > 1.d0) call my_stop("xsref2 must be <= 1.")
  if (xpref1 < 0.d0) call my_stop("xpref1 must be >= 0.")
  if (xpref2 < xpref1) call my_stop("xpref2 must be >= xpref1")
  if (xpref2 > 1.d0) call my_stop("xpref2 must be <= 1.")

end subroutine read_inputs

!=============================================================================80
!
! Prints error and stops or warns for bad namelist read
!
!=============================================================================80
subroutine namelist_check(nmlname, errcode, action_missing_nml)

  character(*), intent(in) :: nmlname
  integer, intent(in) :: errcode
  character(*), intent(in) :: action_missing_nml

  if (errcode < 0) then
    write(*,*)
    if (trim(action_missing_nml) == 'warn') then
      write(*,'(A)') 'Warning: namelist '//trim(nmlname)//&
                     ' not found in input file.'
      write(*,'(A)') 'Using default values.'
      write(*,*)
    else
      write(*,'(A)') 'Warning: namelist '//trim(nmlname)//&
                     ' is required and was not found in input file.'
      write(*,*)
      stop
    end if
  else if (errcode > 0) then
    write(*,*)
    write(*,'(A)') 'Error: unrecognized variable in namelist '//trim(nmlname)//&
                   '.'
    write(*,'(A)') 'See User Guide for correct variable names.'
    write(*,*)
    stop
  else
    continue
  end if

end subroutine namelist_check

!=============================================================================80
!
! Reads command line arguments for input file name and output file prefix
!
!=============================================================================80
subroutine read_clo(input_file, output_prefix)

  use airfoil_operations, only : my_stop

  character(*), intent(inout) :: input_file, output_prefix

  character(80) :: arg
  integer i, nargs
  logical getting_args

  nargs = iargc()
  if (nargs > 0) then
    getting_args = .true.
  else
    getting_args = .false.
  end if

  i = 1
  do while (getting_args)
    call getarg(i, arg) 

    if (trim(arg) == "-i") then
      if (i == nargs) then
        call my_stop("Must specify an input file with -i option.")
      else
        call getarg(i+1, input_file)
        i = i+2
      end if
    else if (trim(arg) == "-o") then
      if (i == nargs) then
        call my_stop("Must specify an output prefix with -o option.")
      else
        call getarg(i+1, output_prefix)
        i = i+2
      end if
    else
      call my_stop("Unrecognized option "//trim(arg)//".")
    end if

    if (i > nargs) getting_args = .false.
  end do

end subroutine read_clo

!=============================================================================80
!
! Asks user to turn off pitching moment constraints
!
!=============================================================================80
function ask_moment_constraints()

  character :: ask_moment_constraints
  logical :: valid_choice

! Get user input

  valid_choice = .false.
  do while (.not. valid_choice)
  
    write(*,*)
    write(*,'(A)') 'Warning: pitching moment constraints not recommended for '
    write(*,'(A)', advance='no') 'symmetrical airfoil optimization. '//&
                                 'Turn them off now? (y/n): '
    read(*,'(A)') ask_moment_constraints

    if ( (ask_moment_constraints == 'y') .or.                                  &
         (ask_moment_constraints == 'Y') ) then
      valid_choice = .true.
      ask_moment_constraints = 'y'
      write(*,*)
      write(*,*) "Setting moment_constraint_type(:) = 'none'."
    else if ( (ask_moment_constraints == 'n') .or.                             &
         (ask_moment_constraints == 'N') ) then
      valid_choice = .true.
      ask_moment_constraints = 'n'
    else
      write(*,'(A)') 'Please enter y or n.'
      valid_choice = .false.
    end if

  end do

end function ask_moment_constraints

!=============================================================================80
!
! Asks user to turn off forced transition
!
!=============================================================================80
function ask_forced_transition()

  character :: ask_forced_transition
  logical :: valid_choice

! Get user input

  valid_choice = .false.
  do while (.not. valid_choice)
  
    write(*,*)
    write(*,'(A)') 'Warning: using max-xtr optimization but xtript or xtripb'
    write(*,'(A)', advance='no') 'is less than 1. Set them to 1 now? (y/n): '
    read(*,'(A)') ask_forced_transition

    if ( (ask_forced_transition == 'y') .or.                                  &
         (ask_forced_transition == 'Y') ) then
      valid_choice = .true.
      ask_forced_transition = 'y'
      write(*,*)
      write(*,*) "Setting xtript and xtripb to 1."
    else if ( (ask_forced_transition == 'n') .or.                             &
         (ask_forced_transition == 'N') ) then
      valid_choice = .true.
      ask_forced_transition = 'n'
    else
      write(*,'(A)') 'Please enter y or n.'
      valid_choice = .false.
    end if

  end do

end function ask_forced_transition

end module input_output
