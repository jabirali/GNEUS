! This module defines the data type 'superconductor', which models the physical state of a superconductor. The type is
! a member of class(conductor), and thus inherits internal structure and generic methods defined in module_conductor.
!
! Author:  Jabir Ali Ouassou <jabirali@switzerlandmail.ch>
! Created: 2015-07-17
! Updated: 2015-07-23

module mod_superconductor
  use mod_system
  use mod_spin
  use mod_green
  use mod_conductor
  implicit none

  ! Type declaration
  type, extends(conductor) :: superconductor
    real(dp)                 :: temperature = 1e-6_dp                               ! Temperature of the system (relative to the critical temperature of a bulk superconductor)
    real(dp)                 :: coupling                                            ! BCS coupling constant that defines the strength of the superconductor (dimensionless)
    complex(dp), allocatable :: gap(:)                                              ! Superconducting order parameter as a function of position (relative to the zero-temperature gap of a bulk superconductor)
  contains
    procedure                :: usadel_equation  => superconductor_usadel_equation  ! Differential equation that describes the superconductor
    procedure                :: update_fields    => superconductor_update_fields    ! Updates the superconducting order parameter from the Green's function
    procedure                :: set_gap          => superconductor_set_gap          ! Updates the superconducting order parameter from a given scalar
    procedure                :: get_gap          => superconductor_get_gap          ! Returns the superconducting order parameter at a given position
    procedure                :: get_gap_mean     => superconductor_get_gap_mean     ! Returns the superconducting order parameter average in the material
    procedure                :: get_temperature  => superconductor_get_temperature  ! Returns the current temperature of the material
    procedure                :: set_temperature  => superconductor_set_temperature  ! Updates the current temperature of the material
  end type

  ! Type constructor
  interface superconductor
    module procedure superconductor_construct
  end interface

  ! Type string
  interface type_string
    module procedure type_string_superconductor
  end interface
contains
  pure function superconductor_construct(energy, gap, coupling, thouless, scattering, points) result(this)
    ! Constructs a superconductor object initialized to a superconducting state.
    type(superconductor)              :: this        ! Superconductor object that will be constructed
    real(dp),    intent(in)           :: energy(:)   ! Discretized energy domain that will be used
    complex(dp), intent(in)           :: gap         ! Superconducting order parameter
    real(dp),    intent(in)           :: coupling    ! BCS coupling constant
    real(dp),    intent(in), optional :: thouless    ! Thouless energy       (default: conductor default)
    real(dp),    intent(in), optional :: scattering  ! Imaginary energy term (default: conductor default)
    integer,     intent(in), optional :: points      ! Number of positions   (default: conductor default)
    integer                           :: n           ! Loop variable

    ! Call the superclass constructor
    this%conductor = conductor_construct(energy, gap=gap, thouless=thouless, scattering=scattering, points=points)

    ! Allocate memory (if necessary)
    if (.not. allocated(this%gap)) then
      allocate(this%gap(size(this%location)))
    end if

    ! Initialize the superconducting order parameter
    call this%set_gap(gap)

    ! Initialize the BCS coupling constant
    this%coupling = coupling
  end function

  pure subroutine superconductor_destruct(this)
    ! Define the type destructor.
    type(superconductor), intent(inout) :: this

    ! Deallocate memory (if necessary)
    if(allocated(this%gap)) then
      deallocate(this%gap)
    end if

    ! Call the superclass destructor
    call conductor_destruct(this%conductor)
  end subroutine

  subroutine superconductor_usadel_equation(this, z, g, gt, dg, dgt, d2g, d2gt)
    ! Use the Usadel equation to calculate the second derivatives of the Riccati parameters at point z.
    class(superconductor), intent(in)  :: this
    real(dp),              intent(in)  :: z
    type(spin),            intent(in)  :: g, gt, dg, dgt
    type(spin),            intent(out) :: d2g, d2gt
    type(spin)                         :: N, Nt
    complex(dp)                        :: gap, gapt

    ! Lookup the superconducting order parameter
    gap  = this%get_gap(z)/this%thouless
    gapt = conjg(gap)

    ! Calculate the normalization matrices
    N   = spin_inv( pauli0 - g*gt )
    Nt  = spin_inv( pauli0 - gt*g )

    ! Calculate the second derivatives of the Riccati parameters
    d2g  = (-2.0_dp,0.0_dp)*dg*Nt*gt*dg - (0.0_dp,2.0_dp)*this%erg*g  - gap  * pauli2 + gapt * g*pauli2*g
    d2gt = (-2.0_dp,0.0_dp)*dgt*N*g*dgt - (0.0_dp,2.0_dp)*this%erg*gt + gapt * pauli2 - gap  * gt*pauli2*gt
  end subroutine

  subroutine superconductor_update_fields(this)
    ! Updates the superconducting order parameter based on the Green's functions of the system.
    class(superconductor), intent(inout) :: this                      ! Superconductor object that will be updated
    real(dp), allocatable                :: gap_real(:), dgap_real(:) ! Real part of the superconducting order parameter and its derivative
    real(dp), allocatable                :: gap_imag(:), dgap_imag(:) ! Imag part of the superconducting order parameter and its derivative
    complex(dp)                          :: singlet                   ! Singlet component of the anomalous Green's function at a given point
    real(dp), external                   :: dpchqa                    ! PCHIP function that evaluates an interpolation at a given point
    integer                              :: err                       ! PCHIP error status
    integer                              :: n, m                      ! Loop variables

    ! Allocate workspace memory
    allocate(gap_real(size(this%energy)))
    allocate(gap_imag(size(this%energy)))
    allocate(dgap_real(size(this%energy)))
    allocate(dgap_imag(size(this%energy)))

    do n = 1,size(this%location)
      do m = 1,size(this%energy)
        ! Calculate the singlet component of the anomalous Green's function at this point
        singlet     = ( this%state(m,n)%get_f_s() - conjg(this%state(m,n)%get_ft_s()) )/2.0_dp

        ! Calculate the real and imaginary parts of the gap equation integrand, and store them in arrays
        gap_real(m) =  dble(singlet) * this%coupling * tanh(0.8819384944310228_dp * this%energy(m)/this%temperature)
        gap_imag(m) = aimag(singlet) * this%coupling * tanh(0.8819384944310228_dp * this%energy(m)/this%temperature)
      end do

      ! Create a PCHIP interpolation of the numerical results above
      call dpchez(size(this%energy), this%energy, gap_real, dgap_real, .false., 0, 0, err)
      call dpchez(size(this%energy), this%energy, gap_imag, dgap_imag, .false., 0, 0, err)

      ! Perform a numerical integration of the interpolation, and update the superconducting order parameter
      this%gap(n) = cmplx( dpchqa(size(this%energy), this%energy, gap_real, dgap_real, 0.0_dp, cosh(1.0_dp/this%coupling), err), &
                           dpchqa(size(this%energy), this%energy, gap_imag, dgap_imag, 0.0_dp, cosh(1.0_dp/this%coupling), err), &
                           kind=dp )
    end do

    ! Deallocate workspace memory
    deallocate(gap_real)
    deallocate(gap_imag)
    deallocate(dgap_real)
    deallocate(dgap_imag)
  end subroutine

  pure subroutine superconductor_set_gap(this, gap)
    ! Updates the superconducting order parameter from a scalar.
    class(superconductor), intent(inout) :: this
    complex(dp),           intent(in   ) :: gap
    integer                              :: n

    do n = 1,size(this%gap)
      this%gap(n) = gap
    end do
  end subroutine

  pure function superconductor_get_gap(this, location) result(gap)
    ! Returns the superconducting order parameter at the given location.
    class(superconductor), intent(in) :: this
    real(dp),              intent(in) :: location
    complex(dp)                       :: gap
    integer                           :: n

    ! Calculate the index corresponding to the given location
    n = nint(location*(size(this%location)-1) + 1)

    ! Extract the superconducting order parameter at that point
    gap = this%gap(n)
  end function

  pure function superconductor_get_gap_mean(this) result(gap)
    ! Returns the superconducting order parameter average in the material.
    class(superconductor), intent(in)  :: this
    complex(dp)                        :: gap

    gap = sum(this%gap)/max(1,size(this%gap)) 
  end function

  pure function superconductor_get_temperature(this) result(temperature)
    ! Returns the superconductor temperature.
    class(superconductor), intent(in) :: this
    real(dp)                          :: temperature

    temperature = this%temperature
  end function

  pure subroutine superconductor_set_temperature(this, temperature)
    ! Updates the superconductor temperature.
    class(superconductor), intent(inout) :: this
    real(dp),              intent(in   ) :: temperature

    this%temperature = temperature
  end subroutine

  function type_string_superconductor(this) result(str)
    ! Implementation of the type_string interface, which can be used to ascertain
    ! whether a class(conductor) object is of the specific type(superconductor).
    type(superconductor), intent(in) :: this
    character(len=14)                :: str

    str = 'SUPERCONDUCTOR'
  end function
end module
