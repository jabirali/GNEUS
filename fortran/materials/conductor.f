!> Author:   Jabir Ali Ouassou
!> Category: Materials
!>
!> This module defines the data type 'conductor', which models the physical state of a conductor for a discretized range
!> of positions and energies.  It has two main applications: (i) it can be used as a base type for more exotic materials,
!> such as superconductors and ferromagnets; (ii) it can be used in conjunction with such materials in hybrid structures.
!>
!> @TODO
!>   Move the the spinactive field into separate subobjects spinactive_a and spinactive_b of a type(spinactive). This
!>   type can be moved into a module spinactive_m, together with the associated methods diffusion_spinorbit etc. We can
!>   then have separate modules spinorbit_m and spinactive_m that the current module depends on, leading to greater 
!>   encapsulation and separation. The spinreflect.i contents are removed, but may be reintroduced if necessary.

module conductor_m
  use :: stdio_m
  use :: math_m
  use :: spin_m
  use :: nambu_m
  use :: propagator_m
  use :: material_m
  use :: spinorbit_m
  use :: spinactive_m
  use :: spinscattering_m
  private

  ! Type declarations
  type, public, extends(material) :: conductor
    ! These parameters represent the physical fields in the material
    real(wp)                          :: depairing              =  0.00_wp                    !! Magnetic orbital depairing
    type(spinactive),     allocatable :: spinactive_a                                         !! Spin-active interface
    type(spinactive),     allocatable :: spinactive_b                                         !! Spin-active interface
    type(spinscattering), allocatable :: spinscattering                                       !! Spin-dependent scattering
    type(spinorbit),      allocatable :: spinorbit                                            !! Spin-orbit coupling
  contains
    ! These methods are required by the class(material) abstract interface
    procedure                 :: init                    => conductor_init                    !! Initializes propagators
    procedure                 :: diffusion_equation_a    => conductor_diffusion_equation_a    !! Boundary condition (left)
    procedure                 :: diffusion_equation_b    => conductor_diffusion_equation_b    !! Boundary condition (right)
    procedure                 :: update_prehook          => conductor_update_prehook          !! Code to execute before updates
    procedure                 :: update_posthook         => conductor_update_posthook         !! Code to execute after  updates

    ! These methods contain the equations that describe electrical conductors
    procedure                 :: diffusion_equation      => conductor_diffusion_equation      !! Diffusion equation (conductor terms)

    ! These methods define miscellaneous utility functions
    procedure                 :: conf                    => conductor_conf                    !! Configures material parameters
  end type

  ! Type constructors
  interface conductor
    module procedure conductor_construct
  end interface
contains

  !--------------------------------------------------------------------------------!
  !                        IMPLEMENTATION OF CONSTRUCTORS                          !
  !--------------------------------------------------------------------------------!

  function conductor_construct() result(this)
    !! Constructs a conductor object initialized to a superconducting state.
    type(conductor) :: this

    ! Initialize locations
    allocate(this%location(151))
    call linspace(this%location, 0 + 1e-10_wp, 1 - 1e-10_wp)

    ! Initialize energies
    allocate(this%energy(600))
    call linspace(this%energy(   :400), 1e-6_wp, 1.50_wp)
    call linspace(this%energy(400:500), 1.50_wp, 4.50_wp)
    call linspace(this%energy(500:   ), 4.50_wp, 30.0_wp)

    ! Initialize propagators
    allocate(this%propagator(size(this%energy),size(this%location)))
    call this%init( (0.0_wp,0.0_wp) )

    ! Allocate memory for physical observables
    allocate(this % correlation(size(this % location)))
    allocate(this % supercurrent(0:7,size(this % location)))
    allocate(this % lossycurrent(0:7,size(this % location)))
    allocate(this % accumulation(0:7,size(this % location)))
    allocate(this % density(size(this % energy), size(this % location), 0:7))

    ! Allocate boundary condition objects
    allocate(this % spinactive_a)
    allocate(this % spinactive_b)
  end function

  pure subroutine conductor_init(this, gap)
    !! Define the default initializer.
    class(conductor),      intent(inout) :: this
    complex(wp), optional, intent(in)    :: gap
    integer                              :: n, m

    ! Initialize the Riccati parameters
    if (present(gap)) then
      do m = 1,size(this%location)
        do n = 1,size(this%energy)
            this % propagator(n,m) = propagator( cx(this%energy(n),this%scattering), gap )
        end do
      end do
    end if

    ! Initialize the distribution function
    do m = 1,size(this%location)
      do n = 1,size(this%energy)
        ! Finite nonequilibrium potentials
        this % propagator(n,m) % h = &
          [                                                      &
            f(n,+1,+1) + f(n,+1,-1) + f(n,-1,+1) + f(n,-1,-1),   &
            0.0_wp,                                              &
            0.0_wp,                                              &
            f(n,+1,+1) - f(n,+1,-1) + f(n,-1,+1) - f(n,-1,-1),   &
            f(n,+1,+1) + f(n,+1,-1) - f(n,-1,+1) - f(n,-1,-1),   &
            0.0_wp,                                              &
            0.0_wp,                                              &
            f(n,+1,+1) - f(n,+1,-1) - f(n,-1,+1) + f(n,-1,-1)    &
          ]

        ! Transverse applied potentials
        if (this % transverse) then
          this % propagator(n,m) % h(4:7) = 0
        end if
      end do
    end do
  contains
    pure function f(n, c, s) result(h)
      ! Fermi distribution for a given energy (n), charge parity (c=±1), and spin (s=±1).
      integer, intent(in) :: n, c, s
      real(wp)            :: h

      associate (E  => this % energy(n),           &
                 V  => this % voltage     * c,     &
                 Vs => this % spinvoltage * c * s, &
                 T  => this % temperature,         &
                 Ts => this % spintemperature * s  )
        h = tanh(0.8819384944310228_wp * (E+V+Vs)/(T+Ts))/4
      end associate
    end function
  end subroutine

  !--------------------------------------------------------------------------------!
  !                     IMPLEMENTATION OF CONDUCTOR EQUATIONS                      !
  !--------------------------------------------------------------------------------!

  pure subroutine conductor_diffusion_equation(this, e, z, g, gt, dg, dgt, d2g, d2gt)
    !! Use the diffusion equation to calculate the second-derivatives of the Riccati parameters at energy e and point z.
    class(conductor), intent(in)    :: this
    complex(wp),      intent(in)    :: e
    real(wp),         intent(in)    :: z
    type(spin),       intent(in)    :: g, gt, dg, dgt
    type(spin),       intent(inout) :: d2g, d2gt
    type(spin)                      :: N, Nt

    ! Calculate the normalization matrices
    N   = inverse( pauli0 - g*gt )
    Nt  = inverse( pauli0 - gt*g )

    ! Calculate the second-derivatives of the Riccati parameters
    d2g  = (-2.0_wp,0.0_wp)*dg*Nt*gt*dg - (0.0_wp,2.0_wp)*e*g
    d2gt = (-2.0_wp,0.0_wp)*dgt*N*g*dgt - (0.0_wp,2.0_wp)*e*gt

    ! Calculate the contribution from a spin-orbit coupling
    if (allocated(this%spinorbit)) then
      call this%spinorbit%diffusion_equation(g, gt, dg, dgt, d2g, d2gt)
    end if

    ! Calculate the contribution from spin-dependent scattering
    if (allocated(this%spinscattering)) then
      call this%spinscattering%diffusion_equation(g, gt, dg, dgt, d2g, d2gt)
    end if

    ! Calculate the contribution from orbital magnetic depairing
    if (this%depairing > 0) then
      d2g  = d2g  + (this%depairing/this%thouless)*(2.0_wp*N  - pauli0)*g
      d2gt = d2gt + (this%depairing/this%thouless)*(2.0_wp*Nt - pauli0)*gt
    end if
  end subroutine

  pure subroutine conductor_diffusion_equation_a(this, a, g, gt, dg, dgt, r, rt)
    !! Calculate residuals from the boundary conditions at the left interface.
    class(conductor),          intent(in)    :: this
    type(propagator),          intent(in)    :: a
    type(spin),                intent(in)    :: g, gt, dg, dgt
    type(spin),                intent(inout) :: r, rt

    ! Transparent interface: minimize the propagator deviation
    if (this % transparent_a) then
      r  = g  - a % g
      rt = gt - a % gt
      return
    end if

    ! Else: calculate the interface gradient from a matrix current
    call this%spinactive_a%diffusion_equation_a(a, g, gt, dg, dgt, r, rt)

    ! Gauge-dependent terms in the case of spin-orbit coupling
    if (allocated(this%spinorbit)) then
      ! Interface has spin-orbit coupling
      call this%spinorbit%diffusion_equation_a(g, gt, dg, dgt, r, rt)
    end if
  end subroutine

  pure subroutine conductor_diffusion_equation_b(this, b, g, gt, dg, dgt, r, rt)
    !! Calculate residuals from the boundary conditions at the right interface.
    class(conductor),          intent(in)    :: this
    type(propagator),          intent(in)    :: b
    type(spin),                intent(in)    :: g, gt, dg, dgt
    type(spin),                intent(inout) :: r, rt

    ! Transparent interface: minimize the propagator deviation
    if (this % transparent_b) then
      r  = g  - b % g
      rt = gt - b % gt
      return
    end if

    ! Else: calculate the interface gradient from a matrix current
    call this%spinactive_b%diffusion_equation_b(b, g, gt, dg, dgt, r, rt)

    ! Gauge-dependent terms in the case of spin-orbit coupling
    if (allocated(this%spinorbit)) then
      call this%spinorbit%diffusion_equation_b(g, gt, dg, dgt, r, rt)
    end if
  end subroutine

  impure subroutine conductor_update_prehook(this)
    !! Code to execute before running the update method of a class(conductor) object.
    class(conductor), intent(inout) :: this

    ! Usually, we normalize the spin-mixing conductance and other interface parameters to the tunneling conductance. But in
    ! the case of a vacuum interface, we wish to normalize them to the normal-state conductance instead. Since the tunneling
    ! conductance is normalized to the normal conductance, we can achieve this by defining the tunneling conductance to one.
    ! Setting the polarization to zero also disables all but the spin-mixing terms in the spin-active boundary condition.
    if (.not. associated(this % material_a)) then
      this % spinactive_a % conductance  = 1.0
      this % spinactive_a % polarization = 0.0
    end if
    if (.not. associated(this % material_b)) then
      this % spinactive_b % conductance  = 1.0
      this % spinactive_b % polarization = 0.0
    end if

    ! Prepare variables associated with spin-orbit coupling
    if (allocated(this%spinorbit)) then
      call this%spinorbit%update_prehook
    end if

    ! Prepare variables associated with spin-active tunneling  interfaces
    call this % spinactive_a % update_prehook
    call this % spinactive_b % update_prehook

    ! Modify the type string
    this%type_string = color_yellow // 'CONDUCTOR' // color_none
    ! if (allocated(this%spinorbit))       this%type_string = trim(this%type_string) // color_cyan   // ' [SOC]' // color_none
    ! if (norm2(this%spinactive_a%magnetization)>eps) this%type_string = trim(this%type_string)//color_purple //' [SAL]'//color_none
    ! if (norm2(this%spinactive_b%magnetization)>eps) this%type_string = trim(this%type_string)//color_purple //' [SAR]'//color_none
  end subroutine

  impure subroutine conductor_update_posthook(this)
    !! Code to execute after running the update method of a class(conductor) object.
    !! In particular, this function calculates supercurrents, dissipative currents,
    !! accumulations, and density of states, and stores the results in the object.
    use :: nambu_m

    class(conductor), intent(inout)          :: this
    type(nambu), allocatable                 :: gauge
    real(wp),    allocatable, dimension(:,:) :: I, J, Q
    complex(wp), allocatable, dimension(:)   :: S
    integer                                  :: n, m, k

    ! Allocate memory for the workspace
    allocate(S(size(this % energy)))
    allocate(I(size(this % energy), 0:7))
    allocate(J(size(this % energy), 0:7))
    allocate(Q(size(this % energy), 0:7))

    ! Calculate the gauge contribution
    if (allocated(this % spinorbit)) then
      allocate(gauge)
      gauge = diag(+this % spinorbit % Az  % matrix,&
                   -this % spinorbit % Azt % matrix )
    end if

    ! Simplify the namespace
    associate(E => this % energy,     &
              z => this % location,   &
              G => this % propagator, &
              D => this % density     )

      ! Iterate over positions
      do n = 1,size(z)
        ! Calculate the spectral properties at this position
        do m = 1,size(E)
          S(m)     = G(m,n) % correlation()
          Q(m,:)   = G(m,n) % accumulation()
          I(m,:)   = G(m,n) % supercurrent(gauge)
          J(m,:)   = G(m,n) % lossycurrent(gauge)
          D(m,n,:) = G(m,n) % density()
        end do

        ! Superconducting correlations depend on the cutoff
        S = S/acosh(E(size(E)))

        ! Heat and spin-heat observables depend on the energy
        do k = 4,7
          Q(:,k) = E * Q(:,k)
          I(:,k) = E * I(:,k)
          J(:,k) = E * J(:,k)
        end do

        ! Integrate the spectral observables to find the total observables
        this % correlation(n) = integrate(E, S, E(1), E(size(E)))
        do k = 0,7
          this % accumulation(k,n) = integrate(E, Q(:,k), E(1), E(size(E)))
          this % supercurrent(k,n) = integrate(E, I(:,k), E(1), E(size(E)))
          this % lossycurrent(k,n) = integrate(E, J(:,k), E(1), E(size(E)))
        end do
      end do
    end associate

    ! Deallocate workspace memory
    deallocate(S, Q, I, J)

    ! Call the spinorbit posthook
    if (allocated(this%spinorbit)) then
      call this%spinorbit%update_posthook
    end if
  end subroutine



  !--------------------------------------------------------------------------------!
  !                      IMPLEMENTATION OF UTILITY METHODS                         !
  !--------------------------------------------------------------------------------!

  impure subroutine conductor_conf(this, key, val)
    !! Configure a material property based on a key-value pair.
    use :: evaluate_m

    class(conductor), intent(inout) :: this
    character(*),     intent(in)    :: key
    character(*),     intent(in)    :: val
    real(wp)                        :: tmp

    select case(key)
      case ('conductance_a')
        call evaluate(val, this % spinactive_a % conductance)
      case ('conductance_b')
        call evaluate(val, this % spinactive_b % conductance)
      case ('resistance_a')
        call evaluate(val, tmp)
        this % spinactive_a % conductance = 1/tmp
      case ('resistance_b')
        call evaluate(val, tmp)
        this % spinactive_b % conductance = 1/tmp
      case ('spinmixing_a')
        call evaluate(val, this % spinactive_a % spinmixing)
      case ('spinmixing_b')
        call evaluate(val, this % spinactive_b % spinmixing)
      case ('secondorder_a')
        call evaluate(val, this % spinactive_a % secondorder)
      case ('secondorder_b')
        call evaluate(val, this % spinactive_b % secondorder)
      case ('polarization_a')
        call evaluate(val, this % spinactive_a % polarization)
      case ('polarization_b')
        call evaluate(val, this % spinactive_b % polarization)
      case ('magnetization_a')
        call evaluate(val, this % spinactive_a % magnetization)
        this % spinactive_a % magnetization = unitvector(this % spinactive_a % magnetization)
      case ('magnetization_b')
        call evaluate(val, this % spinactive_b % magnetization)
        this % spinactive_b % magnetization = unitvector(this % spinactive_b % magnetization)
      case ('misalignment_a')
        call evaluate(val, this % spinactive_a % misalignment)
        this % spinactive_a % misalignment = unitvector(this % spinactive_a % misalignment)
      case ('misalignment_b')
        call evaluate(val, this % spinactive_b % misalignment)
        this % spinactive_b % misalignment = unitvector(this % spinactive_b % misalignment)
      case ('nanowire')
        call evaluate(val, tmp)
        if (.not. allocated(this % spinorbit)) then
          allocate(this % spinorbit)
          this % spinorbit = spinorbit(this)
        end if
        this % spinorbit % field(3) = this % spinorbit % field(3) + (-tmp)*pauli1
      case ('rashba')
        call evaluate(val, tmp)
        if (.not. allocated(this % spinorbit)) then
          allocate(this % spinorbit)
          this % spinorbit = spinorbit(this)
        end if
        this % spinorbit % field(1) = this % spinorbit % field(1) + (-tmp)*pauli2
        this % spinorbit % field(2) = this % spinorbit % field(2) + (+tmp)*pauli1
      case ('dresselhaus')
        call evaluate(val, tmp)
        if (.not. allocated(this % spinorbit)) then
          allocate(this % spinorbit)
          this % spinorbit = spinorbit(this)
        end if
        this % spinorbit % field(1) = this % spinorbit % field(1) + (+tmp)*pauli1
        this % spinorbit % field(2) = this % spinorbit % field(2) + (-tmp)*pauli2
      case ('depairing')
        call evaluate(val, this % depairing)
      case ('gap')
        block
          integer  :: index
          real(wp) :: gap, phase
          index = scan(val,',')
          if (index > 0) then
            call evaluate(val(1:index-1), gap)
            call evaluate(val(index+1: ), phase)
          else
            call evaluate(val, gap)
            phase = 0
          end if
          call this % init( gap = gap*exp((0.0,1.0)*pi*phase) )
        end block
      case ('scattering_spinflip')
        if (.not. allocated(this % spinscattering)) then
          allocate(this%spinscattering)
          this % spinscattering = spinscattering(this)
        end if
        call evaluate(val, this % spinscattering % spinflip)
      case ('scattering_spinorbit')
        if (.not. allocated(this % spinscattering)) then
          allocate(this%spinscattering)
          this % spinscattering = spinscattering(this)
        end if
        call evaluate(val, this % spinscattering % spinorbit)
      case ('zeroenergy')
        block
          logical :: tmp
          call evaluate(val, tmp)
          if (tmp) then
            deallocate(this % energy)
            allocate(this % energy(1))
            this % energy(1) = 0
          end if
        end block
      case default
        call material_conf(this, key, val)
    end select
  end subroutine
end module
