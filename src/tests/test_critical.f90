! This script calculates the critical temperature of a bulk superconductor, by performing a binary search for the
! temperature where the gap vanishes numerically. The result should be numerically one in the given unit system.
!
! Written by Jabir Ali Ouassou <jabirali@switzerlandmail.ch>
! Created 2015-07-21
! Updated 2015-07-22

program test_critical
  use mod_conductor
  use mod_superconductor
  use mod_multilayer
  use mod_critical
  implicit none

  type(superconductor) :: s                           ! Superconductor
  real(dp)             :: erg(600)                    ! Energy array
  real(dp)             :: coupling      =  0.2000_dp  ! BCS coupling constant
  real(dp)             :: scattering    =  0.0100_dp  ! Imaginary energy term due to inelastic scattering
  complex(dp)          :: gap           =  0.0001_dp  ! Initial superconducting gap (relative to the zero-temperature bulk value)
  real(dp)             :: lower         =  0.0000_dp  ! Lower limit for the critical temperature (relative to the bulk value)
  real(dp)             :: upper         =  1.5000_dp  ! Upper limit for the critical temperature (relative to the bulk value)
  real(dp)             :: length        = 25.0000_dp  ! Length of the superconductor (relative to the correlation length)
  integer              :: iterations    = 25          ! Number of iterations of the binary search
  integer              :: stabilization =  2          ! Number of iterations per temperature
  integer              :: n, m                        ! Loop variables

  ! Initialize the energy array
  call energy_range_positive(erg, coupling)

  ! Initialize the superconductor
  s = superconductor(erg, gap = gap, coupling = coupling, thouless = 1/length**2, scattering = scattering)
  call s%set_temperature( (upper+lower)/2.0_dp )

  ! Perform the binary search for the critical temperature
  call critical_temperature(s, bisections = 10, iterations = 2, lower = 0.0_dp, upper = 1.5_dp, gap = (0.0001_dp,0.0000_dp))

!  ! Perform the binary search for the critical temperature
!  do n=1,iterations
!    ! Initialize a weakly superconducting state
!    call s%initialize( gap )
!    call s%set_gap( gap )
!
!    ! Print status information
!    call print_information
!
!    ! Update the state of the superconductor
!    do m=1,stabilization
!      write(*,'(a,i0,a,i0,a)') ' :: Updating superconductor [',m,'/',stabilization, ']'
!      call s%update
!    end do
!
!    ! Check whether the mean gap has increased, and update the temperature bounds accordingly
!    if (abs(s%get_gap_mean()/gap) >= 1.0_dp) then
!      lower = s%get_temperature()
!    else
!      upper = s%get_temperature()
!    end if
!
!    ! Update the superconductor temperature based on the new bounds
!    call s%set_temperature( (upper+lower)/2.0_dp )
!  end do
!
!  ! Print final results
!  call print_results
contains
  subroutine print_information
    ! Determine how much CPU time has elapsed
    real(sp) :: time
    call cpu_time(time)

    ! Print the progress information to standard out
    write(*,*)
    write(*,'(a)') '╒═══════════════════════════════════╕'
    write(*,'(a)') '│       PROGRESS  INFORMATION       │'
    write(*,'(a)') '├───────────────────────────────────┤'
    write(*,'(a,6x,a,i2.2,a,i2.2,7x,a)')                &
      '│','Binary search: ', n, ' / ', iterations,     '│'
    write(*,'(a,6x,a,f8.6,6x,a)')                       &
      '│','Temperature:   ', s%get_temperature(),      '│'
    write(*,'(a,6x,a,i2.2,a,i2.2,a,i2.2,6x,a)')         &
      '│','Elapsed time:  ',                            &
      int(time/3600.0_sp),':',                          &
      int(mod(time,3600.0_sp)/60.0_sp),':',             &
      int(mod(time,60.0_sp)),                          '│'
    write(*,'(a)') '╘═══════════════════════════════════╛'
  end subroutine

  subroutine print_results
    write(*,*)
    write(*,'(a)') '╒═══════════════════════════════════╕'
    write(*,'(a)') '│           FINAL RESULTS           │'
    write(*,'(a)') '├───────────────────────────────────┤'
    write(*,'(a)') '│       Critical temperature:       │'
    write(*,'(a,8x,f18.16,9x,a)') '│', s%get_temperature(), '│'
    write(*,'(a)') '╘═══════════════════════════════════╛'
  end subroutine
end program
