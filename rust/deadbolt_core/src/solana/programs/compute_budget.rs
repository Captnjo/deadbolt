use crate::crypto::SolanaPublicKey;
use crate::solana::instruction::Instruction;

pub fn program_id() -> SolanaPublicKey {
    SolanaPublicKey::from_base58("ComputeBudget111111111111111111111111111111").unwrap()
}

/// Set the compute unit limit for the transaction.
pub fn set_compute_unit_limit(units: u32) -> Instruction {
    let mut data = vec![0u8; 5];
    data[0] = 2; // SetComputeUnitLimit
    data[1..5].copy_from_slice(&units.to_le_bytes());

    Instruction {
        program_id: program_id(),
        accounts: Vec::new(),
        data,
    }
}

/// Set the compute unit price (priority fee) in micro-lamports per compute unit.
pub fn set_compute_unit_price(micro_lamports: u64) -> Instruction {
    let mut data = vec![0u8; 9];
    data[0] = 3; // SetComputeUnitPrice
    data[1..9].copy_from_slice(&micro_lamports.to_le_bytes());

    Instruction {
        program_id: program_id(),
        accounts: Vec::new(),
        data,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_set_compute_unit_limit() {
        let ix = set_compute_unit_limit(200_000);
        assert_eq!(ix.data[0], 2);
        assert_eq!(ix.data.len(), 5);
        let units = u32::from_le_bytes(ix.data[1..5].try_into().unwrap());
        assert_eq!(units, 200_000);
    }

    #[test]
    fn test_set_compute_unit_price() {
        let ix = set_compute_unit_price(1_000);
        assert_eq!(ix.data[0], 3);
        assert_eq!(ix.data.len(), 9);
        let price = u64::from_le_bytes(ix.data[1..9].try_into().unwrap());
        assert_eq!(price, 1_000);
    }
}
