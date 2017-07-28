!> Author:   Jabir Ali Ouassou
!> Category: Materials
!>
!> This submodule is included by conductor.f, and contains the equations which model spin-active interfaces.
!>
!> @TODO: Rewrite using the new nambu.f library, replacing e.g. diag(m·σ,m·σ*) with m*nambuv(1:3).
!>        Also, we may then for brevity replace matmul(G,matmul(M,G)) with G*M*G, and so on.

module spinactive_m
  use :: propagator_m
  use :: material_m
  use :: math_m
  use :: spin_m
  use :: nambu_m

  ! Type declarations
  type, public :: spinactive
    real(wp)                 :: conductance   = 0.0      !! Interfacial conductance
    real(wp)                 :: polarization  = 0.0      !! Interfacial spin-polarization
    real(wp)                 :: spinmixing    = 0.0      !! Interfacial 1st-order spin-mixing
    real(wp)                 :: secondorder   = 0.0      !! Interfacial 2nd-order spin-mixing
    real(wp), dimension(1:3) :: magnetization = [0,0,1]  !! Interfacial magnetization direction
    real(wp), dimension(1:3) :: misalignment  = [0,0,0]  !! Interfacial magnetization misalignment
  
    complex(wp), dimension(1:4,1:4) :: M  = 0.0          !! Magnetization matrix (transmission)
    complex(wp), dimension(1:4,1:4) :: M0 = 0.0          !! Magnetization matrix (reflection, this  side)
    complex(wp), dimension(1:4,1:4) :: M1 = 0.0          !! Magnetization matrix (reflection, other side)
  contains
    procedure :: diffusion_equation_a => spinactive_diffusion_equation_a
    procedure :: diffusion_equation_b => spinactive_diffusion_equation_b
    procedure :: update_prehook       => spinactive_update_prehook
  end type
contains
  pure subroutine spinactive_update_prehook(this)
    !! Updates the internal variables associated with spin-active interfaces.
    class(spinactive), intent(inout) :: this 
  
    ! Process transmission properties (both sides of interfaces)
    call update_magnetization(this % M, this % magnetization)
  
    ! Default reflection properties match transmission properties
    this % M0 = this % M
    this % M1 = this % M
  
    ! Process reflection properties (this side of interfaces)
    call update_magnetization(this % M0, this % misalignment)
    call update_magnetization(this % M0, this % misalignment)
  
    ! ! Process reflection properties (other side of interfaces)
    ! if (associated(this % material_a)) then
    !   select type (other => this % material_a)
    !     class is (conductor)
    !       call update_magnetization(this % spinactive_a % M1, other % spinactive_b % misalignment)
    !   end select
    ! end if
  
    ! if (associated(this % material_b)) then
    !   select type (other => this % material_b)
    !     class is (conductor)
    !       call update_magnetization(this % spinactive_b % M1, other % spinactive_a % misalignment)
    !   end select
    ! end if
  contains
    pure subroutine update_magnetization(matrix, vector)
      !! Updates a magnetization matrix based on the content of an allocatable magnetization vector. 
      !! If the magnetization vector is not allocated, then the magnetization matrix is not updated.
      real(wp),    intent(in)    :: vector(:)
      complex(wp), intent(inout) :: matrix(4,4)
  
      if (norm2(vector) > eps) then
        matrix(1:2,1:2) = vector(1) * pauli1 + vector(2) * pauli2 + vector(3) * pauli3
        matrix(3:4,3:4) = vector(1) * pauli1 - vector(2) * pauli2 + vector(3) * pauli3
      end if
    end subroutine
  end subroutine
  
  pure subroutine spinactive_diffusion_equation_a(this, a, g1, gt1, dg1, dgt1, r1, rt1)
    !! Calculate the spin-active terms in the left boundary condition, and update the residuals.
    class(spinactive), target,  intent(in)    :: this
    type(propagator),           intent(in)    :: a
    type(spin),                 intent(in)    :: g1, gt1, dg1, dgt1
    type(spin),                 intent(inout) :: r1, rt1
    complex(wp), dimension(4,4)               :: GM0, GM1, I
    type(propagator)                          :: GR0, GR1
  
    ! Calculate the 4×4 matrix propagators
    associate(g0 => a % g, gt0 => a % gt)
      GR0 = propagator(g0, gt0)
      GR1 = propagator(g1, gt1)

      GM0 = GR0 % retarded()
      GM1 = GR1 % retarded()
    end associate
  
    ! Calculate the 4×4 matrix current
    I = 0.25 * this%conductance &
      * spinactive_current(GM1, GM0, this%M, this%M0, this%M1, &
        this%polarization, this%spinmixing, this%secondorder)
  
    ! Calculate the deviation from the boundary condition
    r1  = dg1  + (pauli0 - g1*gt1) * (I(1:2,3:4) - I(1:2,1:2)*g1)
    rt1 = dgt1 + (pauli0 - gt1*g1) * (I(3:4,1:2) - I(3:4,3:4)*gt1)
  end subroutine
  
  pure subroutine spinactive_diffusion_equation_b(this, b, g2, gt2, dg2, dgt2, r2, rt2)
    !! Calculate the spin-active terms in the right boundary condition, and update the residuals.
    class(spinactive), target,  intent(in)    :: this
    type(propagator),           intent(in)    :: b
    type(spin),                 intent(in)    :: g2, gt2, dg2, dgt2
    type(spin),                 intent(inout) :: r2, rt2
    complex(wp), dimension(4,4)               :: GM2, GM3, I
    type(propagator)                          :: GR2, GR3
  
    ! Calculate the 4×4 matrix propagators
    associate(g3 => b % g, gt3 => b % gt)
      GR2 = propagator(g2, gt2)
      GR3 = propagator(g3, gt3)

      GM2 = GR2 % retarded()
      GM3 = GR3 % retarded()
    end associate
  
    ! Calculate the 4×4 matrix current
    I = 0.25 * this%conductance &
      * spinactive_current(GM2, GM3, this%M, this%M0, this%M1, &
      this%polarization, this%spinmixing, this%secondorder)
  
    ! Calculate the deviation from the boundary condition
    r2  = dg2  - (pauli0 - g2*gt2) * (I(1:2,3:4) - I(1:2,1:2)*g2)
    rt2 = dgt2 - (pauli0 - gt2*g2) * (I(3:4,1:2) - I(3:4,3:4)*gt2)
  end subroutine
  
  pure function spinactive_current(G0, G1, M, M0, M1, P, Q, R) result(I)
    !! Calculate the matrix current at an interface with spin-active properties. The equations
    !! implemented here should be valid for an arbitrary interface polarization, and up to 2nd
    !! order in the transmission probabilities and spin-mixing angles of the interface. 
    complex(wp), dimension(4,4), intent(in) :: G0, G1      !! Propagator matrices
    complex(wp), dimension(4,4), intent(in) :: M0, M1, M   !! Magnetization matrices 
    real(wp),                    intent(in) :: P,  Q,  R   !! Interface parameters
    complex(wp), dimension(4,4)             :: S0, S1      !! Matrix expressions
    complex(wp), dimension(4,4)             :: I           !! Matrix current
  
    ! Shortcut-evaluation for nonmagnetic interfaces
    if (abs(Q) == 0 .and. abs(P) == 0) then
      I = commutator(G0, G1)
      return
    end if
  
    ! Evaluate the 1st-order matrix functions
    S0 = spinactive_current1_transmission(G1)
    S1 = spinactive_current1_reflection()
  
    ! Evaluate the 1st-order matrix current
    I  = commutator(G0, S0 + S1)
  
    ! Calculate the 2nd-order contributions to the matrix current. Note that we make a
    ! number of simplifications in this implementation. In particular, we assume that 
    ! all interface parameters except the magnetization directions are equal on both
    ! sides of the interface. We also assume that the spin-mixing angles and tunneling
    ! probabilities of different channels have standard deviations that are much smaller
    ! than their mean values, which reduces the number of new fitting parameters to one.
  
    if (abs(R) > 0) then
      ! Evaluate the 1st-order matrix functions
      S1 = spinactive_current1_transmission(matmul(G1,matmul(M1,G1)) - M1) 
  
      ! Evaluate the 2nd-order matrix current
      I = I                                     &
        + spinactive_current2_transmission()    &
        + spinactive_current2_crossterms()      &
        + spinactive_current2_reflection()
    end if
  contains
    pure function spinactive_current1_transmission(G) result(F)
      !! Calculate the 1st-order transmission terms in the matrix current commutator.
      complex(wp), dimension(4,4), intent(in) :: G
      complex(wp), dimension(4,4)             :: F
      real(wp) :: Pr, Pp, Pm
  
      Pr = sqrt(1 - P**2)
      Pp = 1 + Pr
      Pm = 1 - Pr
  
      F = G + (P/Pp) * anticommutator(M,G) + (Pm/Pp) * matmul(M,matmul(G,M))
    end function
  
    pure function spinactive_current1_reflection() result(F)
      !! Calculate the 1st-order spin-mixing terms in the matrix current commutator.
      complex(wp), dimension(4,4) :: F
  
      F = ((0,-1)*Q) * M0
    end function
  
    pure function spinactive_current2_transmission() result(I)
      !! Calculate the 2nd-order transmission terms in the matrix current.
      complex(wp), dimension(4,4) :: I
  
      I = (0.50*R/Q) * matmul(S0,matmul(G0,S0))
    end function
  
    pure function spinactive_current2_reflection() result(I)
      !! Calculate the 2nd-order spin-mixing terms in the matrix current.
      complex(wp), dimension(4,4) :: I
  
      I = (0.25*R*Q) * commutator(G0, matmul(M0,matmul(G0,M0)))
    end function
  
    pure function spinactive_current2_crossterms() result(I)
      !! Calculate the 2nd-order cross-terms in the matrix current.
      complex(wp), dimension(4,4) :: I
  
      I = ((0.00,0.25)*R) * commutator(G0, matmul(S0,matmul(G0,M0)) + matmul(M0,matmul(G0,S0)) + S1)
    end function
  end function
end module
